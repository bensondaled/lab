--Ben Deverett 2019
-- "click" the target twice with a specific temporal delay between clicks 1 and 2

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
-- phase constants
local PHASE_PRE_BEGIN = 0
local PHASE_PRE_FIRST_CLICK = 1
local PHASE_PRE_SECOND_CLICK = 2
-- durations
local TIME_TO_FIXATE_CROSS = 1 -- in frames
local TARGET_INTERVAL = 200
local INTERVAL_TOLERANCE = 100
local INTERTRIAL_INTERVAL = 60
-- target aesthetics
local TARGET_SIZE = .1
local TARGET_LOCATION = {.5, .25}
local TARGET_COLOR = {50,200,230}
local TARGET_COLOR_2 = {200,230,50}
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

    -- graphics setup
    self.screenSize = opts.screenSize
    self:setupImages()
    self:setupCoordinateBounds(CANVAS_SIZE, PRE_RENDER_MASK_SIZE)
    
    -- task param inits
    self._trialPhase = PHASE_PRE_BEGIN
    self._click_t0 = nil

    -- point and click api
    self.pac = pac
    
  end
  
  function env:setupImages()
    self.images = {}

    self.images.fixation = psychlab_helpers.getFixationImage(self.screenSize,
                 BG_COLOR, FIXATION_COLOR, FIXATION_SIZE)
  end

  -- trial methods --
  
  function env:showTarget()

    self:widgetsOff({'fixation','center_of_fixation'})

    target = tensor.ByteTensor(self.screenSize.height*TARGET_SIZE, self.screenSize.width*TARGET_SIZE, 3):fill(TARGET_COLOR)
    self.pac:addWidget{
        name = 'target',
        image = target,
        pos = psychlab_helpers.getUpperLeftFromCenter(TARGET_LOCATION, TARGET_SIZE),
        size = {TARGET_SIZE,TARGET_SIZE},
        mouseClickCallback = self.clickCallback,
    }
    
  end

  function env:finishTrial(delay)
    self._trialPhase = PHASE_PRE_BEGIN
    self._click_t0 = nil
    self.currentTrial.blockId = self.blockId
    self.currentTrial.reactionTime =
        game:episodeTimeSeconds() - self._currentTrialStartTime

    self.pac:resetSteps()

    psychlab_helpers.publishTrialData(self.currentTrial, kwargs.schema)
    psychlab_helpers.finishTrialCommon(self, delay, FIXATION_SIZE)
    self.pac:removeWidget('target')
  end

  -- callbacks --

  function env:fixationCallback(name, mousePos, hoverTime, userData)
    if hoverTime == TIME_TO_FIXATE_CROSS and self._trialPhase==PHASE_PRE_BEGIN then
          self.currentTrial.stepCount = 0
          self.pac:addReward(FIXATION_REWARD)
          self._stepsSinceInteraction = 0
          self._trialPhase = PHASE_PRE_FIRST_CLICK
          self._currentTrialStartTime = game:episodeTimeSeconds()
          self:showTarget()
    end

  end

  function env:step(lookingAtScreen)
    -- auto-called at each tick; increment counter to allow measurement of reaction times in steps
    if self.currentTrial.stepCount ~= nil then
      self.currentTrial.stepCount = self.currentTrial.stepCount + 1
    end
    
  end

  function env:clickCallback(name, mousePos, hoverTime, userData)

      if self._trialPhase == PHASE_PRE_FIRST_CLICK then

          new_target = tensor.ByteTensor(self.screenSize.height*TARGET_SIZE, self.screenSize.width*TARGET_SIZE, 3):fill(TARGET_COLOR_2)
          self.pac:updateWidget('target', new_target)
          self._trialPhase = PHASE_PRE_SECOND_CLICK
          self._click_t0 = self.pac:elapsedSteps()

      elseif self._trialPhase == PHASE_PRE_SECOND_CLICK then
          -- end trial
          local elapsed = self.pac:elapsedSteps() - self._click_t0
          abs_dif = math.abs(elapsed - TARGET_INTERVAL)
        
          if abs_dif < INTERVAL_TOLERANCE then
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
    
  end

  -- helpers --
  
  function env:widgetsOff(widgets)
    for i,w in ipairs(widgets) do
      self.pac:removeWidget(w)
  end
  end
    
  function env:removeArray()
    --self.pac:removeWidget('target')
    self.pac:removeWidget('main_image')
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

  function env:renderFrame(coords) --

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
