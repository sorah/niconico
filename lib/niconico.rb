# -*- coding: utf-8 -*-

require 'rubygems'
require 'mechanize'
require 'cgi'

class Niconico
  URL = {
    login: 'https://secure.nicovideo.jp/secure/login?site=niconico',
    watch: 'http://www.nicovideo.jp/watch/',
    getflv: 'http://flapi.nicovideo.jp/api/getflv'
  }

  TEST_VIDEO_ID = "sm9"

  attr_reader :agent, :logined

  def initialize(mail, pass)
    @mail = mail
    @pass = pass

    @logined = false

    @agent = Mechanize.new.tap do |agent|
      agent.ssl_version = 'SSLv3'
    end
  end

  def login(force=false)
    return false if !force && @logined

    page = @agent.post(URL[:login], 'mail' => @mail, 'password' => @pass)

    raise LoginError, "Failed to login (x-niconico-authflag is 0)" if page.header["x-niconico-authflag"] == '0'
    @logined = true
  end

  def inspect
    "#<Niconico: #{@mail} (#{@logined ? "" : "not "}logined)>"
  end
  class LoginError < StandardError; end
end

require_relative './niconico/video'
require_relative './niconico/mylist'
require_relative './niconico/ranking'
