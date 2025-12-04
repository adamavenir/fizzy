module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      Rails.logger.info "[ActionCable] Connection attempt: path=#{request.path}, referrer=#{request.referrer}"
      result = set_current_user
      Rails.logger.info "[ActionCable] set_current_user returned: #{result.inspect}"
      result || reject_unauthorized_connection
    end

    private
      def set_current_user
        session = find_session_by_cookie
        Rails.logger.info "[ActionCable] Session: #{session.inspect}"
        return nil unless session

        account = find_account
        Rails.logger.info "[ActionCable] Account: #{account.inspect}"
        return nil unless account

        Current.account = account
        user = session.identity.users.find_by(account: account)
        Rails.logger.info "[ActionCable] User: #{user.inspect}"
        self.current_user = user if user
      end

      def find_account
        Rails.logger.info "[ActionCable] find_account - env keys: #{request.env.keys.grep(/account|fizzy/).inspect}"
        Rails.logger.info "[ActionCable] find_account - path: #{request.path}"
        Rails.logger.info "[ActionCable] find_account - params: #{request.params.inspect}"
        Rails.logger.info "[ActionCable] find_account - headers origin: #{request.headers['Origin']}"

        # Try to get account from request environment (set by middleware for HTTP requests)
        if account_id = request.env["fizzy.external_account_id"]
          Rails.logger.info "[ActionCable] Found account from env: #{account_id}"
          return Account.find_by(external_account_id: account_id)
        end

        # For WebSocket connections, extract account from path
        # Path format: /949254567/... or just /cable
        if request.path =~ %r{^/(\d{7,})}
          Rails.logger.info "[ActionCable] Found account from path: #{$1}"
          return Account.find_by(external_account_id: $1)
        end

        # Fallback: try to get from referrer (the page that opened the WebSocket)
        if request.referrer && request.referrer =~ %r{/(\d{7,})/}
          Rails.logger.info "[ActionCable] Found account from referrer: #{$1}"
          return Account.find_by(external_account_id: $1)
        end

        # Last resort: get from session's user
        if session = find_session_by_cookie
          if user = session.identity.users.first
            Rails.logger.info "[ActionCable] Found account from session user: #{user.account_id}"
            return user.account
          end
        end

        Rails.logger.info "[ActionCable] Could not find account!"
        nil
      end

      def find_session_by_cookie
        Session.find_signed(cookies.signed[:session_token])
      end
  end
end
