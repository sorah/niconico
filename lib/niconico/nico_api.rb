require 'json'

class Niconico
  class NicoAPI
    class ApiError < Exception; end
    class AcquiringTokenError < Exception; end

    MYLIST_ITEM_TYPES = {video: 0, seiga: 5}

    def initialize(parent)
      @parent = parent
    end

    def agent; @parent.agent; end

    def token; @token ||= get_token; end

    def get_token
      page = agent.get(Niconico::URL[:my_mylist])
      match = page.search("script").map(&:inner_text).grep(/\tNicoAPI\.token/) {|v| v.match(/\tNicoAPI\.token = "(.+)";\n/)}.first
      if match
        match[1]
      else
        raise AcquiringTokenError, "Couldn't find a token"
      end
    end

    def mylist_add(group_id, item_type, item_id, description='')
      !!post(
        '/api/mylist/add',
        {
          group_id: group_id,
          item_type: MYLIST_ITEM_TYPES[item_type],
          item_id: item_id,
          description: description,
          token: token
        }
      )
    end

    private

    def post(path, params)
      uri = URI.join(Niconico::URL[:top], path)
      page = agent.post(uri, params)
      json = JSON.parse(page.body)
      raise ApiError, json unless json['status'] == 'ok'
      json
    end

  end
end
