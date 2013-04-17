vagrant-test-subject
====================

A wrapper around a Vagrant VM, to ease using it as a test subject from rspec and other ruby testing tools.

# Synopsis

    describe "TrafficServer Service" do
      before(:all) do
        @vm = VagrantTestSubject::VM.attach()
      end
      it "should appear as a healthy service" do    
        @vm.should have_running_service("trafficserver")
      end
      it "should be listening on localhost:80" do
        @vm.should be_listening_on_localhost(80)
      end
      it "should be listening on external_ip:80" do
        @vm.should be_listening_on_external_ip(80)
      end
      it "should be the right process name on port 80" do
        process = @vm.process_name_listening('127.0.0.1', 80)
        process.should_not be_nil
        process.should match(/\/opt\/ts\/bin\/traffic_manager/)
      end
      it "should respond with HTTP 200 to / on port 80" do
        @vm.http_get('/').should be_http_ok
      end
    end
    
# Maturity

Alpha.
