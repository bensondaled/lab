--Ben Deverett 2019

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
local FIXATION_COLOR = {255, 0, 0} -- RGB
local BUTTON_SIZE = 0.1
local BG_COLOR = 0
local CENTER = {.5, .5}
local INTERFRAME_INTERVAL = 4 -- in REAL (Labyrinth) frames

-- task params
local TIME_TO_FIXATE_CROSS = 1 -- in frames
local TIME_TO_FIXATE_TARGET = 1
local INTERTRIAL_INTERVAL = 1
-- targets
local N_POSITIONS = 8
local TARGET_DISTANCE = .4
local TARGET_SIZE = .05
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
    log.info('opts passed to _init:\n' .. helpers.tostring(opts))

    self._stepsSinceInteraction = 0

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
      local angle = (i-1) * math.pi / 4
      self.targetPositions[i] = {xLoc(angle), yLoc(angle)}
    end

    -- point and click api
    self.pac = pac
  end
  
  function env:setupImages()
    self.images = {}

    self.images.fixation = psychlab_helpers.getFixationImage(self.screenSize,
                                                             BG_COLOR,
                                                             FIXATION_COLOR,
                                                             FIXATION_SIZE)

    local h = BUTTON_SIZE * self.screenSize.height
    local w = BUTTON_SIZE * self.screenSize.width

    self.images.greenImage = tensor.ByteTensor(h, w, 3):fill{100, 255, 100}
    self.images.redImage = tensor.ByteTensor(h, w, 3):fill{255, 100, 100}
    self.images.blackImage = tensor.ByteTensor(h, w, 3)

  end

  -- trial methods --

  function env:readyPhase()

    --[[ init trial by selecting a target location
    self.currentTrial.goPosition,goIdx = psychlab_helpers.randomFrom(self.targetPositions)

    local readyIdx = goIdx - 1
    if readyIdx < 1 then
        readyIdx = N_POSITIONS - readyIdx
    end
    self.currentTrial.readyPosition = self.targetPositions[readyIdx]

    local setIdx = readyIdx - 1
    if setIdx < 1 then
        setIdx = N_POSITIONS - setIdx
    end
    self.currentTrial.setPosition = self.targetPositions[setIdx]

     self.pac:addWidget{
         name = i,
         image = arrow,
         pos = self.arrowPositions[k],
         size = {5,5},
         mouseHoverCallback = self.correctResponseCallback,
         imageLayer = 3,
     }
    
    --
    local upperLeftPosition = psychlab_helpers.getUpperLeftFromCenter(
        CENTER,
        ANIMATION_SIZE_AS_FRACTION_OF_SCREEN[1]
    )

    -- Display the first frame for the duration of the study interval
    self.animation.currentFrame = self:renderFrame(
        positions(1),
        indicesToTrack,
        self.images.studyCircle
    )
    self.pac:addWidget{
        name = 'main_image',
        image = self.animation.currentFrame,
        pos = upperLeftPosition,
        size = kwargs.animationSizeAsFractionOfScreen,
    }
    self.pac:updateWidget('main_image', self.animation.currentFrame)
    self.pac:addTimer{
        name = 'study_interval',
        timeout = kwargs.studyInterval,
        callback = function(...) return self.trackingPhase(self,
                                                           positions) end
    }
    ]]
  end

  function env:finishTrial(delay)
    self._stepsSinceInteraction = 0
    self.currentTrial.blockId = self.blockId
    self.currentTrial.reactionTime =
        game:episodeTimeSeconds() - self._currentTrialStartTime

    -- Convert radians to degrees before logging
    self.currentTrial.targetDirection =
      math.floor(self.currentTrial.targetDirection * (180 / math.pi) + 0.5)
    psychlab_helpers.publishTrialData(self.currentTrial, kwargs.schema)
    psychlab_helpers.finishTrialCommon(self, delay, FIXATION_SIZE)
  end

  function env:fixationCallback(name, mousePos, hoverTime, userData)
    if hoverTime == TIME_TO_FIXATE_CROSS then
      self._stepsSinceInteraction = 0
      self.pac:addReward(FIXATION_REWARD)
      self.pac:removeWidget('fixation')
      self.pac:removeWidget('center_of_fixation')
    
      self._currentTrialStartTime = game:episodeTimeSeconds()
      self.currentTrial.stepCount = 0

      self:readyPhase()
    end
  end

  -- callbacks --

  function env:step(lookingAtScreen)
    -- auto-called at each tick; increment counter to allow measurement of reaction times in steps
    if self.currentTrial.stepCount ~= nil then
      self.currentTrial.stepCount = self.currentTrial.stepCount + 1
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

  function env:correctResponseCallback(name, mousePos, hoverTime, userData)
    if hoverTime == TIME_TO_FIXATE_TARGET then
      self.currentTrial.response = name
      self.currentTrial.correct = 1
      self.pac:addReward(CORRECT_REWARD)
      self:finishTrial(INTERTRIAL_INTERVAL)
    end
  end

  -- helpers --
    
  function env:removeArray()
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

  function env:renderFrame(coords) -- TODO: fill out this method

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
    self.animation.nextFrame = self:renderFrame(self.animation.state) -- TODO: give proper argument
    -- update the reference called currentFrame to point to the next tensor
    self.animation.currentFrame = self.animation.nextFrame
  end

  return psychlab_factory.createLevelApi{
    env = point_and_click,
    envOpts = {
        environment = env, screenSize = SCREEN_SIZE
    },
    episodeLengthSeconds = 150
  }
end

return factory
