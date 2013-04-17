module VagrantTestSubject
  class VM
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
  end
end
