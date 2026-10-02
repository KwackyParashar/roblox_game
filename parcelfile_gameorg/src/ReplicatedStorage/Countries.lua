local Countries = {}

Countries.Order = { "Home", "StubCountry" } -- progression order, first = starting country

Countries.Data = {
	Home = {
		Name = "Home Cart",
		Cost = 0, -- starting country, free
		Tooltip = "Where it all began.",
	},
	StubCountry = {
		Name = "??? (Test Country)",
		Cost = 250,
		Tooltip = "A placeholder stop — real menu coming soon.",
	},
}

function Countries.Get(id)
	return Countries.Data[id]
end

function Countries.NextAfter(id)
	for i, name in ipairs(Countries.Order) do
		if name == id then
			return Countries.Order[i + 1] -- nil if already last
		end
	end
	return nil
end

return Countries