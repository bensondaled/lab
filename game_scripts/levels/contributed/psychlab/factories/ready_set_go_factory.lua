--Ben Deverett 2019
-- like Jayazeri 2015 RSG reproduction timing task: produce a Set-Go interval matched in duration to the presented Ready-Set interval

-- todo:
-- determine mapping of frames to seconds, if needed

local game = require 'dmlab.system.game'
local psychlab_factory = require 'factories.psychlab.factory'
local psychlab_helpers = require 'factories.psychlab.helpers'
local tensor = require 'dmlab.system.tensor'
local point_and_click = require 'factories.psychlab.point_and_click'
local log = require 'common.log'
local helpers = require 'common.helpers'
local random = require 'common.random'

-- display params
local CANVAS_SIZE = 2048
local PRE_RENDER_MASK_SIZE = 1224
local GAUSSIAN_MASK_SIGMA = 0.15

-- task screen params
local ANIMATION_SIZE_AS_FRACTION_OF_SCREEN = {0.8, 0.8}
local SCREEN_SIZE = {width = 512, height = 512}
local FIXATION_SIZE = 0.1
local FIXATION_COLOR = {50,50,50}
local BUTTON_SIZE = 0.1
local BG_COLOR = 0
local CENTER = {.5, .5}
local INTERFRAME_INTERVAL = 4 -- in REAL (Labyrinth) frames

-- task params
-- durations
local TIME_TO_FIXATE_CROSS = 1 -- in frames
local FIXATION_BREAK_THRESH = 10
local PRE_RSG_DELAYS = {50, 60, 70, 80, 90} -- "variable foreperiod" in paper
local TARGET_DISPLAY_TIME = 100 -- 0.5 s in paper
local RSG_INTERVALS = {150,175,200}
local RSG_FLASH_DURATION = 20
local INTERTRIAL_INTERVAL = 60
local BASE_TOLERANCE = 50
local TOLERANCE_SCALING = 0.25 -- for expanding green band in fig 1c
-- target aesthetics
local N_POSITIONS = 4
local TARGET_DISTANCE = .4
local TARGET_SIZE = .1
local READY_COLOR = {255, 10, 10}
local SET_COLOR = {255, 255, 10}
local GO_COLOR = {10, 200, 10}
-- rewards
local FIXATION_REWARD = 0
local CORRECT_REWARD = 1
local INCORRECT_REWARD = 0

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

  -- init methods --

  function env:_init(pac, opts)
    self.screenSize = opts.screenSize
    --log.info('opts passed to _init:\n' .. helpers.tostring(opts))

    self._stepsSinceInteraction = 0
    self._trialBegan = false
    self._fixationBrokenFrames = 0

    self:setupImages()
    self:setupCoordinateBounds(CANVAS_SIZE, PRE_RENDER_MASK_SIZE)

    local function xLoc(angle)
      return CENTER[1] + (TARGET_DISTANCE * math.cos(angle)) - (TARGET_SIZE / 2)
    end
    local function yLoc(angle)
      return 1 - (CENTER[2] + (TARGET_DISTANCE * math.sin(angle)) + (TARGET_SIZE / 2))
    end

    self.targetPositions = {}
    for i = 1, N_POSITIONS do
      local angle = (i-1) * math.pi / (N_POSITIONS/2)
      self.targetPositions[i] = {xLoc(angle), yLoc(angle)}
    end

    -- point and click api
    self.pac = pac
    
  end
  
  function env:setupImages()
    self.images = {}

    self.images.fixation = psychlab_helpers.getFixationImage(self.screenSize,
                 BG_COLOR, FIXATION_COLOR, FIXATION_SIZE)
  end

  -- trial methods --
  
  function env:preReadyPhase()

    self._currentTrialStartTime = game:episodeTimeSeconds()

    -- determine pre-RSG interval timing for this trial
    local predelay, idx = psychlab_helpers.randomFrom(PRE_RSG_DELAYS)
    predelay = TARGET_DISPLAY_TIME + predelay
    -- determine RSG interval timing for this trial
    local interval, idx = psychlab_helpers.randomFrom(RSG_INTERVALS)
    self._interval = interval

    -- determine "go" widget position, which will determine all others
    local go_pos, idx = psychlab_helpers.randomFrom(self.targetPositions)
    
    -- add "go" widget
    go = tensor.ByteTensor(self.screenSize.height*TARGET_SIZE, self.screenSize.width*TARGET_SIZE, 3):fill(GO_COLOR)
    self.pac:addWidget{
        name = 'go',
        image = go,
        pos = go_pos,
        size = {TARGET_SIZE,TARGET_SIZE},
        mouseHoverCallback = self.goCallback,
    }
    
    -- determine "ready" widget position based on "go" position
    local ready_idx = idx - 2
    if ready_idx < 1 then
        ready_idx = ready_idx + N_POSITIONS
    end
    
    -- start timer to trigger "ready" phase
    self.pac:addTimer{
        name = 'ready_timer',
        timeout = predelay,
        callback = function(...) return self.readyPhase(self, ready_idx, interval) end
    }


  end

  function env:readyPhase(idx, interval)

    local ready_pos = self.targetPositions[idx]

    -- add "ready" widget
    ready = tensor.ByteTensor(self.screenSize.height*TARGET_SIZE, self.screenSize.width*TARGET_SIZE, 3):fill(READY_COLOR)
    self.pac:addWidget{
        name = 'ready',
        image = ready,
        pos = ready_pos,
        size = {TARGET_SIZE,TARGET_SIZE},
    }

    -- determine "set" widget position based on "ready" position
    local set_idx = idx + 1
    if set_idx > N_POSITIONS then
        set_idx = set_idx - N_POSITIONS
    end
    
    -- start timer to flash off "ready" symbol
    self.pac:addTimer{
        name = 'ready_off_timer',
        timeout = RSG_FLASH_DURATION,
        callback = function(...) return self.widgetsOff(self, {'ready'}) end
    }

    -- start timer to trigger "set" phase
    self.pac:addTimer{
        name = 'set_timer',
        timeout = interval,
        callback = function(...) return self.setPhase(self, set_idx, interval) end
    }

  end

  function env:setPhase(idx, interval)
      
    local pos = self.targetPositions[idx]

      -- add "set" widget
    set = tensor.ByteTensor(self.screenSize.height*TARGET_SIZE, self.screenSize.width*TARGET_SIZE, 3):fill(SET_COLOR)
    self.pac:addWidget{
        name = 'set',
        image = set,
        pos = pos,
        size = {TARGET_SIZE,TARGET_SIZE},
    }

    -- start timer to flash off "set" symbol and fixation cross
    self.pac:addTimer{
        name = 'set_off_timer',
        timeout = RSG_FLASH_DURATION,
        callback = function(...) return self.widgetsOff(self, {'set','fixation','center_of_fixation'}) end
    }

    -- now it's the go phase - i.e. we start timing from the onset of the "set" phase in order to measure the set-go interval
    self._fixationRequired = false
    self.goTime = game:episodeTimeSeconds()
    self.goTimeSteps = self.pac:elapsedSteps()
  end

  function env:fixationBroken()
        self:removeArray()
        self:finishTrial(INTERTRIAL_INTERVAL)
  end

  function env:finishTrial(delay)
    self.pac:removeWidget('go')

    self._stepsSinceInteraction = 0
    self._fixationRequired = false
    self._trialBegan = false
    self.currentTrial.blockId = self.blockId
    self.currentTrial.reactionTime =
        game:episodeTimeSeconds() - self._currentTrialStartTime

    self.pac:resetSteps()

    psychlab_helpers.publishTrialData(self.currentTrial, kwargs.schema)
    psychlab_helpers.finishTrialCommon(self, delay, FIXATION_SIZE)
  end

  -- callbacks --

  function env:fixationCallback(name, mousePos, hoverTime, userData)
    if hoverTime == TIME_TO_FIXATE_CROSS and self._trialBegan ~= true then
          self:preReadyPhase()
          self.currentTrial.stepCount = 0
          self.pac:addReward(FIXATION_REWARD)
          self._stepsSinceInteraction = 0
          self._fixationRequired = true
          self._trialBegan = true
          self._fixationBrokenFrames = 0
    end

    if self._fixationRequired == true then
        self._fixationBrokenFrames = 0
    end
  end

  function env:step(lookingAtScreen)
    -- auto-called at each tick; increment counter to allow measurement of reaction times in steps
    if self.currentTrial.stepCount ~= nil then
      self.currentTrial.stepCount = self.currentTrial.stepCount + 1
    end
    
    if self._fixationRequired == true then
        if self._fixationBrokenFrames > FIXATION_BREAK_THRESH then
            self:fixationBroken()
        end
        self._fixationBrokenFrames = self._fixationBrokenFrames + 1
    end
    
    -- TODO: include this feature if desired
    -- If too long since interaction with any buttons, then end episode. This
    -- should speed up the early stages of training, since it causes less time
    -- to be spent looking away from the screen.
    --self._stepsSinceInteraction = self._stepsSinceInteraction + 1
    --if self._stepsSinceInteraction > MAX_IDLE_STEPS then
    --  self.pac:endEpisode()
    --end
  end

  function env:goCallback(name, mousePos, hoverTime, userData)
        
      --log.info('saccade at step:\n' .. helpers.tostring(self.pac:elapsedSteps()))
      --local elapsed = game:episodeTimeSeconds() - self.goTime
      local elapsed = self.pac:elapsedSteps() - self.goTimeSteps
      local dif = elapsed - self._interval
      local abs_dif = math.abs(dif)

      self.currentTrial.response = name
          
      --log.info('(produced - correct) interval in frames:\n' .. helpers.tostring(dif))
      --
    
      local tolerance = BASE_TOLERANCE + TOLERANCE_SCALING * self._interval
    
      if abs_dif < tolerance then
          self.currentTrial.correct = 1
          self.pac:addReward(CORRECT_REWARD)
          log.info('+1 reward')
     else
          self.currentTrial.correct = 0
          self.pac:addReward(INCORRECT_REWARD)
          log.info('no reward')
      end
      
      self:finishTrial(INTERTRIAL_INTERVAL)
  end

  -- helpers --
  
  function env:widgetsOff(widgets)
    for i,w in ipairs(widgets) do
      self.pac:removeWidget(w)
  end
  end
    
  function env:removeArray()
    self.pac:removeWidget('main_image')
    self.pac:removeWidget('fixation')
    self.pac:removeWidget('center_of_fixation')
    self.pac:removeWidget('ready')
    self.pac:removeWidget('set')
    self.pac:removeWidget('go')
    self.pac:clearTimers()
  end
  
  function env:reset(episodeId, seed, ...)
    random:seed(seed)

    self.pac:setBackgroundColor{BG_COLOR, BG_COLOR, BG_COLOR}
    self.pac:clearWidgets()
    
    psychlab_helpers.addFixation(self, FIXATION_SIZE)
    self.reward = 0
    self:initAnimation(ANIMATION_SIZE_AS_FRACTION_OF_SCREEN)

    self.currentTrial = {}

    -- blockId groups together all rows written during the same episode
    self.blockId = seed
  end

  function env:setupCoordinateBounds(canvasSize, preRenderMaskSize)
    local preRenderLowerBound = math.floor((canvasSize - preRenderMaskSize) / 2)
    local preRenderUpperBound = canvasSize - preRenderLowerBound
    local function isAboveLowerBound(coord)
      return coord > preRenderLowerBound
    end
    local function isBelowUpperBound(coord)
      return coord < preRenderUpperBound
    end
    self.isInBounds = function (coord)
      return isAboveLowerBound(coord) and isBelowUpperBound(coord)
    end
  end

  function env:initAnimation(sizeAsFractionOfScreen)
    local imageHeight = sizeAsFractionOfScreen[1] * self.screenSize.height
    local imageWidth = sizeAsFractionOfScreen[2] * self.screenSize.width
    self.animation = {
        currentFrame = tensor.ByteTensor(imageHeight, imageWidth, 3):fill(0),
        nextFrame = tensor.ByteTensor(imageHeight, imageWidth, 3):fill(0),
        imageSize = imageHeight,  -- Assume height and width are the same
    }
    local sigma = GAUSSIAN_MASK_SIGMA
    -- Make gaussian by hand
    local gaussian = tensor.Tensor(imageHeight, imageWidth)
    local cx = 0.5 * imageWidth + 0.5
    local cy = 0.5 * imageHeight + 0.5
    gaussian:applyIndexed(function(_, index)
        local y, x = unpack(index)
        return math.exp(-math.pow((x - cx) / (sigma * imageWidth), 2) / 2
                        -math.pow((y - cy) / (sigma * imageHeight), 2) / 2)
    end)
    self.gaussianMask = gaussian
  end

  function env:renderFrame(coords) -- TODO: fill out this method with anything else needed

    -- coords is a tensor of size [numObjects, 2] describing the coordinates of
    -- each object in the next frame to be displayed after the current frame.
    local frame = tensor.Tensor(unpack(self.animation.nextFrame:shape()))
        :fill(BG_COLOR)

    return frame
  end

  function env:displayFrame(videoCoords, index)

    -- show the current frame
    self.pac:updateWidget('main_image', self.animation.currentFrame)

    -- recursively call this function after the interframe interval
    self.pac:addTimer{
        name = 'interframe_interval',
        timeout = INTERFRAME_INTERVAL,
        callback = function(...) self:displayFrame() end
    }

    -- render the next frame
    self.animation.nextFrame = self:renderFrame()
    -- update the reference called currentFrame to point to the next tensor
    self.animation.currentFrame = self.animation.nextFrame
  end

  return psychlab_factory.createLevelApi{
    env = point_and_click,
    envOpts = {
        environment = env, screenSize = SCREEN_SIZE
    },
  }
end

return factory
