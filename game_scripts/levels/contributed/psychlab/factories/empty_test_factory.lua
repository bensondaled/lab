--[[ BD - minimal working example
--]]


local point_and_click = require 'factories.psychlab.point_and_click'
local psychlab_factory = require 'factories.psychlab.factory'
local tensor = require 'dmlab.system.tensor'

local SCREEN_SIZE = {width = 512, height = 512}

local factory = {}

function factory.createLevelApi(kwargs)
  local env = {}
  env.__index = env

  setmetatable(env, {
      __call = function (cls, ...)
        local self = setmetatable({}, cls)
        self:_init(...)
        return self
      end
  })

  function env:_init(pac, opts)
  end

  return psychlab_factory.createLevelApi{
    env = point_and_click,
    envOpts = { 
        environment = env, screenSize = SCREEN_SIZE
    },
    episodeLengthSeconds = 10
  }
end

return factory
