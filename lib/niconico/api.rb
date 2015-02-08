require 'json'

class Niconico
  class API
    class ApiParseError < Exception; end

    def initialize(parent, token=nil)
      @parent = parent
      @agent = parent.agent
      @token = token || get_token
    end

    def get_token
      page = @agent.get(Niconico::URL[:mymylist])
      if page.search("script").map(&:inner_text).find{|x| /\tNicoAPI\.token/ =~ x }.match(/\tNicoAPI\.token = "(.+)";\n/)
        @token = $1
      else
        raise ApiParseError, 'token can not be acquired'
      end
    end

    def mylist_add group_id, item_type, item_id, description=''
      !!post(
        '/api/mylist/add',
        {
          group_id: group_id,
          # video: 0 seiga: 5
          item_type: item_type,
          item_id: item_id,
          description: description,
          token: @token
        }
      )
    end

    private
    def post path, params
      uri = URI.join(Niconico::URL[:top], path)
      page = @agent.post(uri, params)
      json = JSON.parse(page.body)
      raise ApiParseError, json unless json['status'] == 'ok'
      json
    end
  end
end
