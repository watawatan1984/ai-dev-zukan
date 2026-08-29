module Scheduler
  class VerifySignature
    MAX_CLOCK_SKEW = 5.minutes

    def self.call(timestamp:, signature:, body:, now: Time.current, secret: ENV["GAS_SCHEDULER_SECRET"])
      return false if secret.blank? || timestamp.blank? || signature.blank?

      issued_at = Time.zone.at(Integer(timestamp, 10))
      return false if (now - issued_at).abs > MAX_CLOCK_SKEW

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
      return false unless signature.bytesize == expected.bytesize

      ActiveSupport::SecurityUtils.secure_compare(signature, expected)
    rescue ArgumentError
      false
    end
  end
end
