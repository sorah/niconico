# coding: utf-8
require 'time'
require 'openssl'

class Niconico
  class Live
    class API
      class NoPublicKeyProvided < Exception; end

      URL_GETPLAYERSTATUS = 'http://ow.live.nicovideo.jp/api/getplayerstatus'.freeze
      URL_WATCHINGRESERVATION_LIST = 'http://live.nicovideo.jp/api/watchingreservation?mode=list'

      def initialize(agent)
        @agent = agent
      end

      attr_reader :agent

      def get(id)
        id = normalize_id(id)

        page = agent.get("http://live.nicovideo.jp/gate/#{id}")

        comment_area = page.at("#comment_area#{id}").inner_text

        result = {
          title: page.at('h2 span').inner_text,
          id: id,
          description: page.at('.stream_description .text_area').inner_html,
        }

        kaijo = page.search('.kaijo strong').map(&:inner_text)
        result[:opens_at] = Time.parse("#{kaijo[0]} #{kaijo[1]} +0900")
        result[:starts_at] = Time.parse("#{kaijo[0]} #{kaijo[2]} +0900")

        result[:status] = :scheduled if comment_area.include?('開場まで、あと')
        result[:status] = :on_air if comment_area.include?('現在放送中')
        close_message = comment_area.match(/この番組は(.+?)に終了いたしました。/)
        if close_message
          result[:status] = :closed
          result[:closed_at] = Time.parse("#{close_message[1]} +0900")
        end

        reservation_valid_until_message = comment_area.match(/使用期限: (.+?)まで/)
        if reservation_valid_until_message 
          result[:reservation] = {}
          result[:reservation][:expires_at] = Time.parse("#{reservation_valid_until_message[1]} +0900")

          if comment_area.include?('視聴権を使用し、タイムシフト視聴を行いますか？')
            result[:reservation][:status] = :reserved
            result[:reservation][:available] = true
          elsif comment_area.include?('本番組は、タイムシフト視聴を行う事が可能です。')
            result[:reservation][:status] = :accepted
            result[:reservation][:available] = true
          elsif comment_area.include?('タイムシフト視聴をこれ以上行う事は出来ません。') || comment_area.include?('視聴権の利用期限が過ぎています。')
            result[:reservation][:status] = :outdated
          end
        end

        channel = page.at('div.chan')
        if channel
          result[:channel] = {
            name: channel.at('.shosai a').inner_text,
            id: channel.at('.shosai a')['href'].split('/').last,
            link: channel.at('.shosai a')['href'],
          }
        end

        result
      end

      def heartbeat
        raise NotImplementedError
      end

      def get_player_status(id, public_key = nil)
        id = normalize_id(id)
        page = agent.get("http://ow.live.nicovideo.jp/api/getplayerstatus?locale=GLOBAL&lang=ja%2Djp&v=#{id}&seat%5Flocale=JP")
        if page.body[0] == 'c' # encrypted
          page = Nokogiri::XML(decrypt_encrypted_player_status(page.body, public_key))
        end

        status = page.at('getplayerstatus')

        if status['status'] == 'fail'
          error = page.at('error code').inner_text

          case error
          when 'notlogin'
            return {error: :not_logged_in}
          when 'comingsoon'
            return {error: :not_yet_started}
          when 'closed'
            return {error: :closed}
          when 'require_accept_print_timeshift_ticket'
            return {error: :reservation_not_accepted}
          when 'timeshift_ticket_expire'
            return {error: :reservation_expired}
          when 'noauth'
            return {error: :archive_closed}
          when 'notfound'
            return {error: :not_found}
          else
            return {error: error}
          end
        end

        result = {}

        # Strings
        %w(id title description provider_type owner_name
           bourbon_url full_video kickout_video).each do |key|
          item = status.at(key)
          result[key.to_sym] = item.inner_text if item
        end

        # Integers
        %w(watch_count comment_count owner_id watch_count comment_count).each do |key|
          item = status.at(key)
          result[key.to_sym] = item.inner_text.to_i if item
        end

        # Flags
        %w(is_premium is_reserved is_owner international is_rerun_stream is_archiveplayserver
           archive allow_netduetto
           is_nonarchive_timeshift_enabled is_timeshift_reserved).each do |key|
          item = status.at(key)
          result[key.sub(/^is_/,'').concat('?').to_sym] = item.inner_text == '1' if item
        end

        # Datetimes
        %w(base_time open_time start_time end_time).each do |key|
          item = status.at(key)
          result[key.to_sym] = Time.at(item.inner_text.to_i) if item
        end

        rtmp = status.at('rtmp')
        result[:rtmp] = {
          url: rtmp.at('url').inner_text,
          ticket: rtmp.at('ticket').inner_text,
        }

        ms = status.at('ms')
        result[:ms] = {
          address: ms.at('addr').inner_text,
          port:    ms.at('port').inner_text.to_i,
          thread:  ms.at('thread').inner_text,
        }

        quesheet = status.search('quesheet que')
        result[:quesheet] = quesheet.map do |que|
          {vpos: que['vpos'].to_i, mail: que['mail'], name: que['name'], body: que.inner_text}
        end

        result
      end

      def watching_reservations
        page = agent.get(URL_WATCHINGRESERVATION_LIST)
        page.search('vid').map(&:inner_text).map{ |_| normalize_id(_) }
      end

      def accept_watching_reservation(id_)
        id = normalize_id(id_, with_lv: false)
        page = agent.get("http://live.nicovideo.jp/api/watchingreservation?mode=confirm_watch_my&vid=#{id}&next_url&analytic")
        token = page.at('#reserve img')['onclick'].scan(/'(.+?)'/)[1][0]

        page = agent.post("http://live.nicovideo.jp/api/watchingreservation",
                          accept: 'true', mode: 'use', vid: id, token: token)

        page.at('nicolive_video_response')['status'] == 'ok'
      end

      def decrypt_encrypted_player_status(body, public_key)
        unless public_key
          raise NoPublicKeyProvided,
            'You should provide proper public key to decrypt ' \
            'encrypted player status'
        end

        lines = body.lines
        pubkey = OpenSSL::PKey::RSA.new(public_key)

        encrypted_shared_key = lines[1].unpack('m*')[0]
        shared_key_raw = pubkey.public_decrypt(encrypted_shared_key)
        shared_key = shared_key_raw.unpack('L>*')[0].to_s

        cipher = OpenSSL::Cipher.new('bf-ecb').decrypt
        cipher.padding = 0
        cipher.key_len = shared_key.size
        cipher.key = shared_key

        encrypted_body = lines[2].unpack('m*')[0]

        body = cipher.update(encrypted_body) + cipher.final
        body.force_encoding('utf-8')
      end

      private

      def normalize_id(id, with_lv: true)
        id = id.to_s

        if with_lv
          id.start_with?('lv') ? id : "lv#{id}"
        else
          id.start_with?('lv') ? id[2..-1] : id
        end
      end
    end
  end
end
