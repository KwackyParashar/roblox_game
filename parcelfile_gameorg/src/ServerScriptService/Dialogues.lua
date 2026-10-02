-- Dialogues | ModuleScript | ServerScriptService
-- All conversations live here.
--
-- Step types:
--   { say = "..." }                      customer says a line
--   { you = "..." }                      YOU say a line
--   { order = true }                     the order ticket appears; customer says their order
--   { choice = { {text = "...", steps = { ...more steps... }}, ... } }
--                                        you pick a reply; that option's steps run, then it continues

local Dialogues = {}

-- Names for customers who don't have their own story
Dialogues.Names = { "Sam", "Priya", "Leo", "Noor", "Kai", "Ana", "Ravi", "Zoe", "Tom", "Mei" }

-- STORY CHARACTERS
-- The key (Mira) must match the NAME of a rig inside ServerStorage > Customers.
-- Visits[1] plays the first time she appears, Visits[2] the second time, and so on.
-- After her last visit she chats like a normal customer.
Dialogues.Characters = {
	Beggar = {
		Name = "the old man",
		Visits = {
			{ -- the first day you talk to him
				{ say = "Spare a bit of food, if you can? I won't ask for much." },
				{ order = true },
			},
			{ -- the second day
				{ say = "You again. Most people walk right past me." },
				{ say = "Whatever you can spare is more than enough." },
				{ order = true },
			},
			{ -- the third day
				{ say = "I used to have people who looked out for me too, once." },
				{ order = true },
			},
		},
	},
	Mira = {
		Name = "Mira",
		Visits = {
			{ -- Visit 1
				{ say = "Oh! A new cart. I've walked past this corner a hundred times." },
				{ you = "Just opened today. Welcome!" },
				{ say = "I'm Mira. I paint the sunsets from the hill up there." },
				{ choice = {
					{ text = "You're a painter? That's wonderful!",
						steps = { { say = "Trying to be. Some evenings the colours just won't come out right." } } },
					{ text = "The sunsets here really are something.",
						steps = { { say = "Aren't they? It's why I never leave this town." } } },
				} },
				{ order = true },
			},
			{ -- Visit 2
				{ say = "I'm back! Yesterday's painting turned out better than I expected." },
				{ you = "I'd love to see it sometime." },
				{ say = "Maybe I'll bring it by. Something to hang on your cart." },
				{ order = true },
				{ say = "Take your time. The sky's not going anywhere." },
			},
		},
	},
}

-- EVERYONE ELSE picks one of these at random
Dialogues.Random = {
	{
		{ say = "Evening! Something smells amazing over here." },
		{ you = "Thanks! Long day?" },
		{ say = "The longest. I'm just glad it's sunset." },
		{ order = true },
	},
	{
		{ say = "Hi there!" },
		{ choice = {
			{ text = "Hi! What can I get you?",
				steps = { { say = "Something warm, please. It's getting a bit chilly." } } },
			{ text = "Lovely evening, isn't it?",
				steps = { { say = "It really is. I come this way just for the sky." } } },
		} },
		{ order = true },
	},
	{
		{ say = "I've been thinking about this cart all afternoon." },
		{ you = "That might be the nicest thing anyone's said to me." },
		{ say = "Well, it's true!" },
		{ order = true },
		{ say = "I'll be on that bench over there." },
	},
	{
		{ say = "Quiet tonight, isn't it?" },
		{ you = "Just the way I like it." },
		{ order = true },
	},
}

return Dialogues