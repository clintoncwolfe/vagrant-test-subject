# -*-ruby-*-
Gem::Specification.new do |s|
  s.name        = 'vagrant-test-subject'
  s.version     = '0.0.2'
  s.add_runtime_dependency 'net-ssh'
  s.add_runtime_dependency 'rspec-http'

  s.date        = '2013-04-17'
  s.summary     = "Wrapper class for a Vagrant VM, providing access to testing predicates"
  s.description = "Wrapper class for a Vagrant VM, providing access to testing predicates, such as port map information, process data, ssh connections, and more."
  s.authors     = ["Clinton Wolfe", "Chris Nehren"]
  s.email       = 'clinton@NOSPAM.omniti.com'
  s.files       = [
	           "ChangeLog",
                   "LICENSE",
                   "README.md",
                   "lib/vagrant-test-subject.rb",
                   "lib/vagrant-test-subject/ssh.rb",
                   "lib/vagrant-test-subject/monkey-patches/rspec-http.rb",
                   "lib/vagrant-test-subject/os/redhat.rb",
                   "lib/vagrant-test-subject/os/omnios.rb",
                  ]
  s.homepage    =
    'https://github.com/clintoncwolfe/vagrant-test-subject'

end
