# coding: utf-8
require 'niconico/live/api'

class Niconico
  def live(live_id)
    Live.new(self, live_id)
  end

  class Live
    class ReservationOutdated < Exception; end
    class ReservationNotAccepted < Exception; end
    class TicketRetrievingFailed < Exception; end
    class AcceptingReservationFailed < Exception; end

    def initialize(parent, live_id)
      @parent = parent
      @agent = parent.agent
      @id = @live_id = live_id
      @client = Niconico::Live::API.new(@agent)

      get()
    end

    attr_reader :id, :live, :ticket

    def fetched?
      !!@fetched
    end

    def get(force=false)
      return self if @fetched && !force
      @live = @client.get(@live_id)
      @fetched = true
      self
    end

    def seat(force=false)
      return @seat if @seat && !force
      raise ReservationNotAccepted if reserved? && !reservation_accepted?

      @seat = @client.get_player_status(self.id)

      raise TicketRetrievingFailed, @seat[:error] if @seat[:error]

      @seat
    end

    def accept_reservation
      return self if reservation_accepted?
      raise ReservationOutdated if reservation_outdated?

      result = @client.accept_watching_reservation(self.id)
      raise AcceptingReservationFailed unless result

      get(:reload)

      self
    end

    def inspect
      "#<Niconico::Live: #{id}, #{title}>"
    end

    def title
      get.live[:title]
    end

    def description
      get.live[:description]
    end

    def opens_at
      get.live[:opens_at]
    end

    def starts_at
      get.live[:starts_at]
    end

    def status
      get.live[:status]
    end

    def scheduled?
      status == :scheduled
    end

    def on_air?
      status == :on_air
    end

    def closed?
      status == :closed
    end

    def reserved?
      get.live.key? :reservation
    end

    def reservation_unaccepted?
      reserved? && live[:reservation][:status] == :reserved
    end

    def reservation_accepted?
      reserved? && live[:reservation][:status] == :accepted
    end

    def reservation_outdated?
      reserved? && live[:reservation][:status] == :outdated
    end

    def reservation_available?
      reservation_unaccepted? || reservation_accepted?
    end

    def reservation_expires_at
      reserved? ? live[:reservation][:expires_at] : nil
    end

    def channel
      get.live[:channel]
    end

    def premium?
      !!seat[:premium?]
    end

    def rtmp_url
      seat[:rtmp][:url]
    end

    def ticket
      seat[:rtmp][:ticket]
    end

    def quesheet
      seat[:quesheet]
    end

    def rtmpdump_commands(file_base)
      file_base = File.expand_path(file_base)

      publishes = quesheet.select{ |_| /^\/publish / =~ _[:body] }.map do |publish|
        publish[:body].split(/ /).tap(&:shift)
      end

      plays = quesheet.select{ |_| /^\/play / =~ _[:body] }
 
      plays.map.with_index do |play, i|
        cases = play[:body].sub(/^case:/,'').split(/ /)[1].split(/,/)
        publish_id = nil

        publish_id   = cases.find { |_| _.start_with?('premium:') } if premium?
        publish_id ||= cases.find { |_| _.start_with?('default:') }
        publish_id ||= cases[0]

        publish_id = publish_id.split(/:/).last

        contents = publishes.select{ |_| _[0] == publish_id }

        contents.map.with_index do |content, j|
          content = content[1]
          rtmp = "#{self.rtmp_url}/mp4:#{content}"

          seq = 0
          begin
            file = "#{file_base}.#{i}.#{j}.#{seq}.flv"
            seq += 1
          end while File.exist?(file)

          ['rtmpdump',
           '-V',
           '-o', file,
           '-r', rtmp,
           '-C', "S:#{ticket}",
           '--playpath', "mp4:#{content}",
           '--app', URI.parse(self.rtmp_url).path
          ]
        end
      end.flatten(1)
    end
  end
end
