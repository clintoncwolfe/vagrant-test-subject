module VagrantTestSubject

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
end
