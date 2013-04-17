
# Std lib
require 'tempfile'
require 'json'
require 'net/http'
require 'socket'
require 'timeout'

# Gemfiles
require 'net/ssh'
require 'rspec/http'

# Us!
require 'vagrant-test-subject/monkey-patches/rspec-http'

module VagrantTesting

  # Encapsulates an SSH channel into a VM
  class SSH
    def initialize(vm_name = 'default')
      # Grab ssh config
      config = `vagrant ssh-config`
      
      # Write most of it to a file, grabbing the username and host
      config_file = Tempfile.new("vagrant-ssh-conf")

      host, username = nil, nil
      config.split(/\n/).each do |line|
        case line
        when /^\s+User\s+(\w+)/
          username = $1
        when /^\s+HostName\s+(\S+)/
          host = $1
        when /^\s*Host\s+#{vm_name}/
          # Ignore 
        else
          config_file << line + "\n"
        end
      end
      config_file.flush

      # make a Net::SSH Session
      # and delegate everything to it
      @session = Net::SSH.start(host, username, :config => config_file.path)

      config_file.close
      
    end

    def method_missing(*args, &block)
      method_name = args.shift
      @session.send method_name, *args, &block
    end

  end

  class VM
    attr_reader :ssh, :vbox_guid, :external_ip

    # Factory method, reads VM type and then instantiates 
    def self.attach(vm_name = 'default')
      os_type = VM.read_vbox_os_type(vm_name)

      # Yecch
      vbox_os_to_class = {
        'RedHat_64' => VagrantTesting::VM::RedHat,
        'Red Hat (64 bit)' => VagrantTesting::VM::RedHat,
        'OpenSolaris_64' => VagrantTesting::VM::OmniOS,
      }

      klass = vbox_os_to_class[os_type]
      klass.new(vm_name)
    end

    def initialize(vm_name = 'default')
      @vm_name = vm_name
      @vbox_guid = VM.read_vbox_guid(vm_name)
      @vm_info = `VBoxManage showvminfo #{@vbox_guid} --machinereadable`.split("\n")
      init_port_map()
      @ssh = VagrantTesting::SSH.new(vm_name)
    end


    #================================================#
    #         VM Info Methods
    #================================================#
    def list_internal_ports 
      return @port_map.keys.sort
    end

    def map_port(internal) 
      return @port_map[internal.to_i]
    end

    #================================================#
    #         Testing Helpers
    #================================================#

    # Returns a Net::HTTP::Response 
    def http_get (local_absolute_url)
      uri = URI('http://localhost:' + self.map_port(80).to_s + local_absolute_url)
      response = Net::HTTP.get_response(uri)
    end
    def https_get (local_absolute_url, opts={})
      # TODO - set OpenSSL::SSL::VERIFY_PEER based on opts ?
      uri = URI('http://localhost:' + self.map_port(443).to_s + local_absolute_url)
      response = Net::HTTP.get_response(uri)
    end
    
    #================================================#
    # Testing Predicates
    #================================================#
    def has_running_service? (service_name)
      raise "pure virtual"
    end

    def listening_on_localhost? (vm_port)
      vm_port = vm_port.to_i
      self.listening_ports.find{|lp| ['127.0.0.1', '0.0.0.0', '*'].include?(lp[:ip]) && lp[:port] == vm_port }
    end

    def listening_on_external_ip? (vm_port)
      vm_port = vm_port.to_i
      self.listening_ports.find{|lp| [@external_ip, '0.0.0.0', '*'].include?(lp[:ip]) && lp[:port] == vm_port }
    end

    def has_matching_process_listening? (ip, vm_port, process_regex)
      raise "pure virtual"
    end

    def listening_on_portmap?(vm_port)
      host_port = map_port(vm_port)
      
      # This shit don't work - always connects, even to a port that isn't listening.
      return false

      begin
        #Timeout::timeout(1) do
          begin
            puts "Trying VM host port " + host_port.to_s
            binding.pry
            s = TCPSocket.new('127.0.0.1', host_port )
            s.close
            return true
          rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
            return false
          end
        #end
      #rescue Timeout::Error
      end
      return false
    end

    #================================================#
    #         Guts
    #================================================#
    protected
    def self.read_vbox_guid(vm_name)
      (JSON.parse(IO.read(".vagrant")))['active'][vm_name]
    end
    
    def self.read_vbox_os_type(vm_name)
      vbox_guid = read_vbox_guid(vm_name)
      output = `VBoxManage showvminfo #{vbox_guid} --machinereadable | grep ostype`
      output[/".+"/].gsub('"','')
    end

    def init_port_map
      @port_map = {}
      @vm_info.grep(/Forwarding/) do |rule|
        # Forwarding(0)="2g-183o,tcp,,41080,,80"
        if /Forwarding\(\d+\)="[\w\-]+,(?<proto>\w+),,(?<ext>\d+),,(?<int>\d+)"/ =~ rule then
          @port_map[int.to_i()] = ext.to_i()
        end
      end
    end

    def init_iface_list
      # TODO - populate @external_ip 
      @external_ip = '10.0.2.15'
    end


    class RedHat < VM
      @@SERVICE_NAMES = {
        'trafficserver' => 'trafficserver'
      }

      def initialize(*args)
        super
      end

      def self.register_service_alias(human_name, os_specific_name)
        @@SERVICE_NAMES[human_name] = os_specific_name
      end

      def has_running_service? (human_service_name)
        redhat_service_name = @@SERVICE_NAMES[human_service_name] || human_service_name
        output = self.ssh.exec!("/sbin/service #{redhat_service_name} status; echo exit_code:$?")
        /exit_code:(?<exit_code>\d+)/ =~ output
        return exit_code.to_i == 0 
      end

      def listening_ports
        cmd = "netstat -ln --inet | tail -n +3 | awk '{print $4}'"
        open_ports = []
        self.ssh.exec!(cmd).split("\n").each do |line|
          ip, port = line.split(':')
          next unless ip
          open_ports << { :ip => ip, :port => port.to_i }
        end
        open_ports
      end

      def process_name_listening (ip, vm_port)
        # Note the trailing space after port - prevents 127.0.0.1:80 from matching 127.0.0.1:8084
        cmd = "sudo netstat -lnp --inet | grep '#{ip}:#{vm_port} ' | awk '{print $7}'"
        output = self.ssh.exec!(cmd)
        if output.nil? then
          cmd = "sudo netstat -lnp --inet | grep '0.0.0.0:#{vm_port} ' | awk '{print $7}'"
          output = self.ssh.exec!(cmd)
        end       
        return nil if output.nil?
        output.chomp!

        pid, truncated_process = output.split('/');
        unless pid =~ /^\d+$/ then
          raise "Not sure what this means, when running netstat -nlp:\n#{output}"
        end

        cmd = "ps -fp #{pid} | tail -n +2 | awk '{print $8}'"
        process_string = self.ssh.exec!(cmd).chomp()
        return process_string
      end


    end

    class OmniOS < VM
      def initialize(*args)
        super
      end
    end
  end
end
