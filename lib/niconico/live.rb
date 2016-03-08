# coding: utf-8
require 'niconico/deferrable'
require 'niconico/live/api'

class Niconico
  def live(live_id)
    Live.new(self, live_id)
  end

  class Live
    include Niconico::Deferrable

    class ReservationOutdated < Exception; end
    class ReservationNotAccepted < Exception; end
    class TicketRetrievingFailed < Exception; end
    class AcceptingReservationFailed < Exception; end
    class RtmpdumpFailed < Exception; end

    class << self
      def public_key
        @public_key ||= begin
          if ENV["NICONICO_LIVE_PUBLIC_KEY"]
            File.read(File.expand_path(ENV["NICONICO_LIVE_PUBLIC_KEY"]))
          else
            nil
          end
        end
      end

      def public_key=(other)
        @public_key = other
      end
    end

    def initialize(parent, live_id, preload = nil)
      @parent = parent
      @agent = parent.agent
      @id = @live_id = live_id
      @client = Niconico::Live::API.new(@agent)

      if preload
        preload_deffered_values(preload)
      else
        get
      end
    end

    attr_reader :id, :live, :ticket
    attr_writer :public_key

    def public_key
      @public_key || self.class.public_key
    end

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

      @seat = @client.get_player_status(self.id, self.public_key)

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
      "#<Niconico::Live: #{id}, #{title}#{fetched? ? '': ' (deferred)'}>"
    end

    lazy :title do
      live[:title]
    end

    lazy :description do
      live[:description]
    end

    lazy :opens_at do
      live[:opens_at]
    end

    lazy :starts_at do
      live[:starts_at]
    end

    lazy :status do
      live[:status]
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

    lazy :reservation do
      live[:reservation]
    end

    def reserved?
      !!reservation
    end

    def reservation_available?
      reserved? && reservation[:available]
    end

    def reservation_unaccepted?
      reservation_available? && reservation[:status] == :reserved
    end

    def reservation_accepted?
      reserved? && reservation[:status] == :accepted
    end

    def reservation_outdated?
      reserved? && reservation[:status] == :outdated
    end

    def reservation_expires_at
      reserved? ? reservation[:expires_at] : nil
    end

    lazy :channel do
      live[:channel]
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

    def execute_rtmpdump(file_base, ignore_failure = false)
      rtmpdump_commands(file_base).map do |cmd|
        system *cmd
        retval = $?
        raise RtmpdumpFailed, "#{cmd.inspect} failed" if !retval.success? && !ignore_failure
        [cmd, retval]
      end
    end

    def rtmpdump_commands(file_base)
      case seat[:provider_type]
      when 'community'
        rtmpdump_commands_for_community(file_base)
      else
        rtmpdump_commands_for_official(file_base)
      end
    end

    def rtmpdump_commands_for_community(file_base)
      file_base = File.expand_path(file_base)

      # /publish lv000000000 rtmp://nlpoca000.live.nicovideo.jp:1935/fileorigin/ts_00,/content/20160308/lv000000000_000000000000_0_0f0000.f4v?0000000000:00:deadbeefdeadbeef
      publishes = quesheet.select{ |_| /^\/publish / =~ _[:body] }.map do |publish|
        publish[:body].split(/ /).tap(&:shift)
      end

      # /play rtmp:lv000000000 main
      plays = quesheet.select{ |_| /^\/play / =~ _[:body] }
 
      plays.flat_map.with_index do |play, i|
        publish_id = play[:body].match(/rtmp:(.+?) /)[1]

        contents = publishes.select{ |_| _[0] == publish_id }

        contents.map.with_index do |content, j|
          content = content[1].split(?,)
          rtmp = "#{self.rtmp_url}/#{publish_id}"

          nlplaynotice = [
            content[0],
            "mp4:#{content[1]}",
            "#{content[1].split(?/).last.split(??).first}_0",
          ].join(?,)

          seq = 0
          begin
            file = "#{file_base}.#{i}.#{j}.#{seq}.flv"
            seq += 1
          end while File.exist?(file)

          # requires customized version: https://github.com/sorah/rtmpdump_nicolive/tree/d1c0f5d9a42240e77350534d664451e8fd0a4ec4
          ['rtmpdump',
           '-V',
           '--live',
           '-o', file,
           '-r', rtmp,
           '-C', "S:#{ticket}",
           '-N', nlplaynotice,
          ]
        end
      end
    end

    def rtmpdump_commands_for_official(file_base)
      file_base = File.expand_path(file_base)

      # /publish lv000000000_on0_XXX_0@s00000 /content/20151210/lv000000000_000000000000_0_0a0000.f4v
      publishes = quesheet.select{ |_| /^\/publish / =~ _[:body] }.map do |publish|
        publish[:body].split(/ /).tap(&:shift)
      end

      # "/play case:middle:rtmp:lv000000000_xxxx_xxxx_0@s000000,cam1:rtmp:lv000000000_gd_MNK_00@s00000,cam2:rtmp:lv000000000_gd_MNK_0@s00000,cam0:rtmp:lv000000000_gd_MNK_6@s35997,cam4:rtmp:lv000000000_xxxx_xxxx_0@s000000,default:rtmp:lv000000000_on0_XXX_0@s00000 main"
      plays = quesheet.select{ |_| /^\/play / =~ _[:body] }
 
      plays.flat_map.with_index do |play, i|
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
           '--app', URI.parse(self.rtmp_url).path.sub(/^\//,'')
          ]
        end
      end
    end
  end
end
