--!native

--[[ 
	Animation Controller
	
	Author: LordDogFood
	Written: 30/04/2024
	
	TODO
	1) Fix the type checking mess
	2) Track Sequence playlist for cancellation
]]

local AnimationController = {}
AnimationController.__index = AnimationController

type SequenceFunction = (any) -> ()

type AnimationInfo = {
	ID: string,
	Name: string,
	Speed: number?,
	Weight: number?,
	Looped: boolean?,
	Priority: Enum.AnimationPriority?
}

type SequenceInfo = {
	Name: string,
	Sequence: SequenceFunction
}

type AnimationControllerProps = {
	_animator: Animator,
	
	_loadedAnimations: {[string]: AnimationTrack},
	_playingAnimations: {[string]: AnimationTrack},
	
	_activeSequences: {[string]: {SequenceThread: thread, SequenceInfo: SequenceInfo}},
	_sequences: {[string]: SequenceInfo},
}

export type AnimationControllerInfo = {
	Model: Model,
	Animations: {AnimationInfo},
	OverwriteAnimator: boolean? | true
}

-- Gets or creates a new animator object, creates new animator is forced. (localisation purposes)
local function getInstance(parent: Instance, className: string, overwrite: boolean?)
	
	local instance = parent:FindFirstChildOfClass(className)
	
	if instance and overwrite then
		instance:Destroy()
	end
	
	if not instance then
		instance = Instance.new(className)
		instance.Parent = parent
	end
	
	return instance
end

local function getAnimator(model: Model, overwriteAnimator: boolean?): Animator
	
	local animationController = getInstance(model, "AnimationController")
	local animator = getInstance(animationController, "Animator", overwriteAnimator)
	
	return animator
end

-- Loads the animation using the AnimationProps 
local cachedAnimations = {}
local function loadAnimation(animator: Animator, animationInfo: AnimationInfo): AnimationTrack
	
	local animation = nil
	if cachedAnimations[animationInfo.ID] then
		animation = cachedAnimations[animationInfo.ID]
	else
		animation = Instance.new("Animation")
		animation.AnimationId = animationInfo.ID
		cachedAnimations[animationInfo.ID] = animation
	end
	
	local animationTrack = animator:LoadAnimation(animation)
	
	-- Set animation stats
	animationTrack.Priority = animationInfo.Priority and animationInfo.Priority or animationTrack.Priority
	animationTrack.Looped = animationInfo.Looped and animationInfo.Looped or animationTrack.Looped
	
	animationTrack:AdjustWeight(animationInfo.Weight and animationInfo.Weight or animationTrack.WeightTarget)
	animationTrack:AdjustSpeed(animationInfo.Speed and animationInfo.Speed or animationTrack.Speed)
	
	return animationTrack
end

-- Create the AnimationController class
function AnimationController.new(info: AnimationControllerInfo)
	
	local animator = getAnimator(info.Model, info.OverwriteAnimator)
	
	local loadedAnimations = {}
	for _, animationInfo: AnimationInfo in info.Animations do
		loadedAnimations[animationInfo.Name] = loadAnimation(animator, animationInfo)
	end
	
	local self: AnimationControllerProps = {
		_animator = animator,
		
		_loadedAnimations = loadedAnimations,
		_playingAnimations = {},
		
		_activeSequences = {},
		_sequences = {},
	}
	
	setmetatable(self, AnimationController)
	return self
end

function AnimationController.info(): AnimationControllerInfo
	return {
		Model = nil,
		Animations = {},
		OverwriteAnimator = false,
	}
end

export type AnimationControllerClass = typeof(AnimationController.new(...))

-- Animation Sequences
function AnimationController.NewSequence(self: AnimationControllerClass, sequenceInfo: SequenceInfo)
	
	if self._sequences[sequenceInfo.Name] then
		return warn(`Cannot overwrite existing sequence "{sequenceInfo.Name}"`)
	end
	
	self._sequences[sequenceInfo.Name] = sequenceInfo
end

function AnimationController.PlaySequence(self: AnimationControllerClass, sequenceName: string, ...)
	
	if not self._sequences[sequenceName] then
		return warn(`Could not find sequence "{sequenceName}"`)
	end
	
	if self._activeSequences[sequenceName] then
		return warn(`Cannot play already playing sequence "{sequenceName}"`)
	end
	
	local sequenceInfo = self._sequences[sequenceName]
	local sequenceThread: thread = task.spawn(sequenceInfo.Sequence, ...)
	
	self._activeSequences[sequenceName] = {
		SequenceThread = sequenceThread,
		SequenceInfo = sequenceInfo,
	}
end

-- Play singular animations
function AnimationController.Play(self: AnimationControllerClass, animationName: string, transitionTime: number?, weight: number?, speed: number?): AnimationTrack?
	
	local animationTrack = self._loadedAnimations[animationName]
	if not animationTrack then
		return warn(`Animation "{animationName}" does not exist.`)
	end
	
	if self._playingAnimations[animationName] then
		return warn(`Animation "{animationName}" is already playing.`)
	end
	
	animationTrack:Play(transitionTime, weight, speed)
	self._playingAnimations[animationName] = animationTrack
	
	animationTrack.Stopped:Once(function()
		self._playingAnimations[animationName] = nil
	end)
	
	return animationTrack
end

function AnimationController.Stop(self: AnimationControllerClass, animationName: string, transitionTime: number?)
	
	local playingAnim = self._playingAnimations[animationName]
	if not playingAnim then
		return
	end
	
	playingAnim:Stop(transitionTime)
end

function AnimationController.StopAll(self: AnimationControllerClass, transitionTime: number?)
	for _, track in self._playingAnimations do
		track:Stop(transitionTime)
	end
end

-- Misc
function AnimationController.LoadAnimation(self: AnimationControllerClass, animationInfo: AnimationInfo)
	self._loadedAnimations[animationInfo.Name] = loadAnimation(self._animator, animationInfo)
end

function AnimationController.GetAnimations(self: AnimationControllerClass)
	return self._loadedAnimations
end

function AnimationController.GetPlayingAnimations(self: AnimationControllerClass)
	return self._playingAnimations
end

function AnimationController.RemoveTrack(self: AnimationControllerClass, trackName: string, transitionTime: number?)
	
	if not self._loadedAnimations[trackName] then
		return 
	end
	
	if self._playingAnimations[trackName] then
		self._playingAnimations[trackName]:Stop(0)
	end
	
	self._loadedAnimations[trackName]:Destroy()
	self._loadedAnimations[trackName] = nil
end

function AnimationController.Destroy(self: AnimationControllerClass)
	
	self:StopAll(0)
	
	for trackName, track in self._loadedAnimations do
		self._loadedAnimations[trackName] = nil
		track:Destroy()
	end
end

return AnimationController :: {
	info: () -> AnimationControllerInfo,
	new: (AnimationControllerInfo: AnimationControllerInfo) -> AnimationControllerClass,
}
