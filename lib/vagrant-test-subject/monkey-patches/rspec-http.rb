# What is wrong with you people
module RSpec
  module Http
    class ResponseCodeMatcher
      # Override, this stupidly doesn't work with the stdlib net/http
      def matches?(target)
        @target = target
        if @target.respond_to? :status then
          return @target.status.to_s == @expected_code.to_s
        elsif @target.respond_to? :code then
          # Net::HTTPResponse
          return @target.code.to_s == @expected_code.to_s
        end
      end

      def common_message
        status_code = (@target.respond_to? :status) ? @target.status : @target.code
        message = "have a response code of #{@expected_code}, but got #{status_code}"
        if status_code == 302 || status_code == 201
          message += " with a location of #{@target['Location'] || @target['location']}" 
        end
        message
      end

    end
  end
end
