local model = script.Parent
local humanoid = model:WaitForChild("Humanoid")

-- Ensure the Animator exists
local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

-- Load your walking animation (Replace with your Animation ID)
local animation = Instance.new("Animation")
animation.AnimationId = "rbxassetid://85894478919407" 

local track = animator:LoadAnimation(animation)
track.Looped = true

-- Monitor movement to play/stop the animation
humanoid.Running:Connect(function(speed)
	if speed > 0.1 then
		-- The customer is moving
		if not track.IsPlaying then
			track:Play()
		end
	else
		-- The customer has stopped
		if track.IsPlaying then
			track:Stop()
		end
	end
end)