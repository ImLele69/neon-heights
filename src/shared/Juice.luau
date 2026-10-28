--!strict

-- "game feel": gradients, pulses, pops, flying numbers. in a tycoon this stuff isn't decoration,
-- it's the product, the reward feeling comes almost entirely from here and not from the numbers
-- themselves.
--
-- it's in shared because the server uses it too for effects on the base

local TweenService = game:GetService("TweenService")

local Juice = {}

Juice.PALETTE = {
	ink = Color3.fromRGB(9, 8, 22),
	panel = Color3.fromRGB(22, 18, 48),
	cyan = Color3.fromRGB(0, 245, 255),
	magenta = Color3.fromRGB(255, 0, 190),
	lime = Color3.fromRGB(180, 255, 0),
	amber = Color3.fromRGB(255, 190, 0),
	violet = Color3.fromRGB(170, 90, 255),
	hot = Color3.fromRGB(255, 60, 120),
	white = Color3.fromRGB(255, 255, 255),
	dim = Color3.fromRGB(150, 150, 190),
}

Juice.FONT = Enum.Font.FredokaOne
Juice.FONT_NUM = Enum.Font.LuckiestGuy

-- a hard shadow instead of a soft one: it reads better on small screens and it's the visual
-- vocabulary of the games that work on this platform
function Juice.hardShadow(frame: GuiObject, offset: number)
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Size = frame.Size
	shadow.Position = frame.Position + UDim2.fromOffset(offset, offset)
	shadow.AnchorPoint = frame.AnchorPoint
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.ZIndex = frame.ZIndex - 1
	shadow.Parent = frame.Parent

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 16)
	c.Parent = shadow
	return shadow
end

function Juice.corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function Juice.stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Juice.gradient(parent: Instance, a: Color3, b: Color3, rotation: number): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation
	g.Parent = parent
	return g
end

-- the pop: scale up and bounce back. it's the cheapest feedback there is and carries half of the
-- "satisfying click" on its own
function Juice.pop(obj: GuiObject, amount: number?, duration: number?)
	local base = obj:GetAttribute("BaseSize")
	if base == nil then
		obj:SetAttribute("BaseSize", obj.Size)
		base = obj.Size
	end
	local target = base :: UDim2
	local k = amount or 1.18
	obj.Size =
		UDim2.new(target.X.Scale * k, target.X.Offset * k, target.Y.Scale * k, target.Y.Offset * k)
	TweenService:Create(
		obj,
		TweenInfo.new(duration or 0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = target }
	):Play()
end

-- continuous wobble, draws the eye to what the player should tap now. use it sparingly, or it turns
-- into noise and stops pointing at anything
function Juice.breathe(obj: GuiObject, scale: number, period: number): () -> ()
	local base = obj.Size
	local running = true
	task.spawn(function()
		local t0 = os.clock()
		while running and obj.Parent do
			local phase = (os.clock() - t0) % period / period
			local k = 1 + math.sin(phase * math.pi * 2) * scale
			obj.Size =
				UDim2.new(base.X.Scale * k, base.X.Offset * k, base.Y.Scale * k, base.Y.Offset * k)
			task.wait()
		end
		if obj.Parent then
			obj.Size = base
		end
	end)
	return function()
		running = false
	end
end

-- hue cycling on the border: cheap, and it makes a static panel feel alive
function Juice.rainbowStroke(stroke: UIStroke, period: number): () -> ()
	local running = true
	task.spawn(function()
		local t0 = os.clock()
		while running and stroke.Parent do
			local h = ((os.clock() - t0) % period) / period
			stroke.Color = Color3.fromHSV(h, 0.85, 1)
			task.wait()
		end
	end)
	return function()
		running = false
	end
end

function Juice.shake(obj: GuiObject, intensity: number, duration: number)
	local base = obj.Position
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration and obj.Parent do
			local decay = 1 - (os.clock() - t0) / duration
			obj.Position = base
				+ UDim2.fromOffset(
					math.random(-intensity, intensity) * decay,
					math.random(-intensity, intensity) * decay
				)
			task.wait()
		end
		if obj.Parent then
			obj.Position = base
		end
	end)
end

-- a number that floats up and fades. it's the feedback that turns "the counter changed" into "I
-- earned something"
function Juice.floatText(parent: GuiObject, message: string, color: Color3)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.4)
	label.Position = UDim2.fromScale(0, 0.3)
	label.BackgroundTransparency = 1
	label.Font = Juice.FONT_NUM
	label.Text = message
	label.TextColor3 = color
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.ZIndex = 50
	label.Parent = parent

	TweenService
		:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0, -0.5),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		:Play()
	task.delay(1, function()
		label:Destroy()
	end)
end

-- big numbers count up instead of jumping, watching the counter run is part of the fun of the genre
function Juice.countUp(
	label: TextLabel,
	from: number,
	to: number,
	duration: number,
	fmt: (number) -> string
)
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < duration and label.Parent do
			local a = (os.clock() - t0) / duration
			-- ease-out: starts fast and slows down so the eye can read the final value
			local eased = 1 - (1 - a) ^ 3
			label.Text = fmt(from + (to - from) * eased)
			task.wait()
		end
		if label.Parent then
			label.Text = fmt(to)
		end
	end)
end

return Juice
