# -*- coding: utf-8 -*-
require 'json'
require 'niconico/deferrable'

class Niconico
  def video(video_id)
    login unless @logined
    Video.new(self, video_id)
  end

  class Video
    include Niconico::Deferrable

    deferrable :id, :title,
      :description, :description_raw,
      :url, :video_url, :type,
      :tags, :mylist_comment

    def initialize(parent, video_id, defer=nil)
      @parent = parent
      @agent = parent.agent
      @fetched = false
      @thread_id = @id = video_id
      @page = nil
      @url = "#{Niconico::URL[:watch]}#{@id}"

      if defer
        preload_deffered_values(defer)
      else
        get()
      end
    end

    def economy?; @eco; end

    def get(options = {})
      begin
        @page = @agent.get(@url)
      rescue Mechanize::ResponseCodeError => e
        raise NotFound, "#{@id} not found" if e.message == "404 => Net::HTTPNotFound"
        raise e
      end

      if /^so/ =~ @id
        sleep 5
        @thread_id = @agent.get("#{Niconico::URL[:watch]}#{@id}").uri.path.sub(/^\/watch\//,"")
      end
      additional_params = nil
      if /^nm/ === @id && (!options.key?(:as3) || options[:as3])
        additional_params = "&as3=1"
      end
      getflv = Hash[@agent.get_file("#{Niconico::URL[:getflv]}?v=#{@thread_id}#{additional_params}").scan(/([^&]+)=([^&]+)/).map{|(k,v)| [k.to_sym,CGI.unescape(v)] }]

      if api_data = @page.at("#watchAPIDataContainer")
        video_detail = JSON.parse(api_data.text())["videoDetail"]
        @title ||= video_detail["title"] if video_detail["title"]
        @description ||= video_detail["description"] if video_detail["description"]
        @tags  ||= video_detail["tagList"].map{|e| e["tag"]}
      end

      t = @page.at("#videoTitle")
      @title ||= t.inner_text unless t.nil?
      d = @page.at("div#videoComment>div.videoDescription")
      @description ||= d.inner_html unless d.nil?

      @video_url = getflv[:url]
      if @video_url
        @eco = !(/low$/ =~ @video_url).nil?
        @type = case @video_url.match(/^http:\/\/(.+\.)?nicovideo\.jp\/smile\?(.+?)=.*$/).to_a[2]
                when 'm'; :mp4
                when 's'; :swf
                else;     :flv
                end
      end
      @tags ||= @page.search("#video_tags a[rel=tag]").map(&:inner_text)
      @mylist_comment ||= nil

      @fetched = true
      @page
    end

    def available?
      !!video_url
    end

    def get_video
      raise VideoUnavailableError unless available?
      @agent.get_file(video_url)
    end

    def get_video_by_other
      raise VideoUnavailableError unless available?
      {cookie: @agent.cookie_jar.cookies(URI.parse(@video_url)),
       url: video_url}
    end

    def inspect
      "#<Niconico::Video: #{@id}.#{@type} \"#{@title}\"#{@eco ? " low":""}#{(fetched? && !@video_url) ? ' (unavailable)' : ''}#{fetched? ? '' : ' (defered)'}>"
    end

    class NotFound < StandardError; end
    class VideoUnavailableError < StandardError; end
  end
end
