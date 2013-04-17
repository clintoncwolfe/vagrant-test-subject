
# Std lib
require 'tempfile'
require 'json'
require 'net/http'
require 'socket'
require 'timeout'

# Gemfiles
require 'net/ssh'
require 'rspec/http'

# Our precious self
require 'vagrant-test-subject/monkey-patches/rspec-http'
require 'vagrant-test-subject/ssh'
require 'vagrant-test-subject/os/redhat'
require 'vagrant-test-subject/os/omnios'

module VagrantTestSubject

  class VM
    attr_reader :ssh, :vbox_guid, :external_ip

    # Factory method, reads VM type and then instantiates 
    def self.attach(vm_name = 'default')
      os_type = VM.read_vbox_os_type(vm_name)

      # Yecch
      vbox_os_to_class = {
        'RedHat_64' => VagrantTestSubject::VM::RedHat,
        'Red Hat (64 bit)' => VagrantTestSubject::VM::RedHat,
        'OpenSolaris_64' => VagrantTestSubject::VM::OmniOS,
      }

      klass = vbox_os_to_class[os_type]
      klass.new(vm_name)
    end

    def initialize(vm_name = 'default')
      @vm_name = vm_name
      @vbox_guid = VM.read_vbox_guid(vm_name)
      @vm_info = `VBoxManage showvminfo #{@vbox_guid} --machinereadable`.split("\n")
      init_port_map()
      @ssh = VagrantTestSubject::SSH.new(vm_name)
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
      
      # This doesn't work - always connects, even to a port that isn't listening.
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

  end
end
