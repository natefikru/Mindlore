#if DEBUG
// Generated from the story bible in docs/demo-story.md. Edit the JSON in place; DemoStoryTests
// checks every name, tag, and loose end against the text.
extension DemoStory {
    static let chapter2 = #"""
[
  {
    "date": "2025-12-01T07:40",
    "title": "Ninth is not moving",
    "text": "Coffee at 6:40 because I couldn't sleep. Greg pulled the whole team into a standup and said the ninth is not moving, like it was a fact of physics and not a date he invented in October. Priya said the reconciliation service isn't tested against the volume we'll see at launch. Greg said we'll monitor closely. That's not a plan, that's a hope with a dashboard. Anyway, back to work.",
    "summary": "I couldn't sleep and had coffee at 6:40. At work, Greg treated the ninth as fixed despite Priya's concern that the reconciliation service is not tested for launch volume, and his response felt like hope with a dashboard rather than a plan.",
    "mood": "stressed",
    "secondaryMood": "tired",
    "areas": [
      "work",
      "health"
    ],
    "tags": [
      "coffee",
      "workplace"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Greg"
      },
      {
        "kind": "person",
        "name": "Priya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "health"
        ],
        "names": [],
        "offset": 0,
        "summary": "I had coffee at 6:40 because I couldn't sleep.",
        "tags": [
          "coffee"
        ],
        "topic": "early coffee and sleep"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Greg",
          "Priya"
        ],
        "offset": 41,
        "summary": "Greg set the ninth as a fixed launch date, while Priya raised concerns that the reconciliation service is not tested for launch volume and Greg offered monitoring instead of a plan.",
        "tags": [
          "workplace"
        ],
        "topic": "launch readiness concerns"
      }
    ]
  },
  {
    "date": "2025-12-05T18:30",
    "title": "Christmas gifts and Pickles",
    "text": "Maya came over after her shift with Thai food and we ended up making the family gift list for Christmas because I am hopeless at this every single year. Nina is the hard one, she already has everything and returns what she doesn't love. Maya suggested a soup subscription thing since Nina complained about not having time to cook. Sold. Also apparently Pickles knocked one of the plants off the windowsill while we were eating and just watched it happen, no remorse.",
    "summary": "I made the family Christmas gift list with Maya over Thai food and chose a soup subscription for Nina. Pickles knocked a plant off the windowsill during dinner and showed no remorse.",
    "mood": "connected",
    "secondaryMood": "frustrated",
    "areas": [
      "family",
      "friends"
    ],
    "tags": [
      "gift",
      "thai food",
      "pet mishap",
      "plants"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "person",
        "name": "Nina"
      },
      {
        "kind": "other",
        "name": "Pickles"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "family",
          "friends"
        ],
        "names": [
          "Maya",
          "Nina"
        ],
        "offset": 0,
        "summary": "I made the family Christmas gift list with Maya, including a soup subscription for Nina.",
        "tags": [
          "gift",
          "thai food"
        ],
        "topic": "Christmas gift planning"
      },
      {
        "areasRaw": [
          "home"
        ],
        "names": [
          "Pickles"
        ],
        "offset": 337,
        "summary": "Pickles knocked a plant off the windowsill while I was eating and watched it happen.",
        "tags": [
          "pet mishap",
          "plants"
        ],
        "topic": "Pickles and the plant"
      }
    ]
  },
  {
    "date": "2025-12-07T19:45",
    "title": "Tacos and a spreadsheet",
    "text": "Tacos at Taqueria Lupita with Danny, al pastor and the green salsa like always. He's got a spreadsheet now for El Primo, actual line items, a guy from the health department he needs to call about the truck inspection. I told him that's more progress than my whole team made this week. He asked how the launch prep was going and I said ask me in two weeks. Walked home and the radiator in the bedroom started making this banging noise, like someone hitting a pipe with a wrench. Hoping it's nothing.",
    "summary": "I had tacos with Danny at Taqueria Lupita and heard that El Primo now has detailed line items and a pending truck inspection call. After walking home, I noticed the bedroom radiator making a loud banging noise.",
    "mood": "anxious",
    "areas": [
      "friends",
      "home"
    ],
    "tags": [
      "tacos",
      "food truck",
      "radiator"
    ],
    "mentions": [
      {
        "kind": "place",
        "name": "Taqueria Lupita"
      },
      {
        "kind": "person",
        "name": "Danny"
      },
      {
        "kind": "project",
        "name": "El Primo"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "friends",
          "work"
        ],
        "names": [
          "Taqueria Lupita",
          "Danny",
          "El Primo"
        ],
        "offset": 0,
        "summary": "I had tacos with Danny, heard about his progress on El Primo, and gave a noncommittal update on my own launch prep.",
        "tags": [
          "tacos",
          "food truck"
        ],
        "topic": "Tacos and launch prep"
      },
      {
        "areasRaw": [
          "home"
        ],
        "names": [],
        "offset": 356,
        "summary": "I noticed the bedroom radiator making a loud banging noise and hoped it was nothing serious.",
        "tags": [
          "radiator"
        ],
        "topic": "Bedroom radiator noise"
      }
    ],
    "opens": [
      {
        "about": [
          "Danny",
          "El Primo"
        ],
        "id": "t016",
        "text": "Danny needs to call the health department about the truck inspection"
      }
    ]
  },
  {
    "date": "2025-12-08T22:30",
    "title": "Radiator gives up",
    "text": "No heat in the bedroom at all now, the radiator banging stopped because the whole thing just gave up. Texted Mr. Kowalski, no response yet. Slept in a hoodie. This apartment.",
    "summary": "I have no heat in the bedroom because the radiator stopped working, and I am waiting for Mr. Kowalski to respond after texting him.",
    "mood": "frustrated",
    "secondaryMood": "tired",
    "areas": [
      "home"
    ],
    "tags": [
      "radiator"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Mr. Kowalski"
      }
    ],
    "opens": [
      {
        "about": [
          "Mr. Kowalski"
        ],
        "id": "t017",
        "text": "Wait for Mr. Kowalski to respond about the bedroom radiator"
      }
    ]
  },
  {
    "date": "2025-12-09T23:50",
    "title": "Payouts v2 goes live",
    "text": "Payouts v2 went live at 6am. By ten I had four Slack threads going and Priya on a call with her voice doing the thing it does when she's trying not to yell. The reconciliation job double counted a batch of transactions from the retry queue and started paying merchants twice. Not five merchants. Not fifty. The number by two o'clock was somewhere north of three hundred and climbing every time the job ran again, because nobody had killed the cron. Greg wanted a one line update for his boss before we even had the number confirmed. I told him I wasn't going to give him a wrong number to make him feel better in a meeting. He didn't love that. Ben found the actual bug around four, a flag that got flipped in a config push two days ago that nobody flagged for QA because it was supposed to be dark until launch. Priya killed the job. We spent the rest of the night writing a script to identify every duplicate payout so finance could start clawing them back tomorrow. Left the office at eleven. Ordered a burrito I didn't taste. Pickles was asleep on my keyboard when I finally sat down and I just left him there for a while.",
    "summary": "Payouts v2 went live with a retry-queue bug that caused hundreds of duplicate merchant payments, leading to an all-day incident response. I left work at eleven and found Pickles asleep on my keyboard.",
    "mood": "overwhelmed",
    "secondaryMood": "stressed",
    "areas": [
      "work",
      "home"
    ],
    "tags": [
      "payouts v2",
      "workplace",
      "late night",
      "pet"
    ],
    "mentions": [
      {
        "kind": "project",
        "name": "Payouts v2"
      },
      {
        "kind": "person",
        "name": "Priya"
      },
      {
        "kind": "person",
        "name": "Greg"
      },
      {
        "kind": "person",
        "name": "Ben"
      },
      {
        "kind": "other",
        "name": "Pickles"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Payouts v2",
          "Priya",
          "Greg",
          "Ben"
        ],
        "offset": 0,
        "summary": "I dealt with a growing duplicate-payout incident, pushed back on an unconfirmed update, and worked late on a script to identify the affected transactions.",
        "tags": [
          "payouts v2",
          "workplace"
        ],
        "topic": "duplicate payout incident"
      },
      {
        "areasRaw": [
          "home"
        ],
        "names": [
          "Pickles"
        ],
        "offset": 969,
        "summary": "I left work late, ordered a burrito I barely noticed, and sat with Pickles asleep on my keyboard.",
        "tags": [
          "late night",
          "pet"
        ],
        "topic": "late-night arrival home"
      }
    ],
    "opens": [
      {
        "due": "2025-12-10",
        "id": "t018",
        "text": "Finish identifying duplicate payouts so finance can claw them back"
      }
    ]
  },
  {
    "date": "2025-12-10T22:40",
    "title": "Day two of the mess",
    "text": "Second day of the launch fallout. The clawback script Priya and Ben wrote overnight is not perfect, it flagged nineteen merchants as duplicates who weren't, which means nineteen angry emails from actual merchant accounts saying we took money from them for no reason. Spent the whole morning on the phone with support triaging which flags are real. Greg wants a merchant facing statement by end of day that doesn't use the word bug. I said what word does he want me to use instead and he said impacted. Cool. Great word. Very honest. Priya hasn't left the office in about thirty hours, I made her go home at nine. I'm staying because someone has to watch the retry queue and it might as well be me since it's my project. Ate cold pizza standing at my desk, back at work by seven the next morning. Told Maya I couldn't make it tonight and she just said go handle it, I'm not going anywhere. That helped more than I expected.",
    "summary": "I spent the second day of the launch fallout triaging false duplicate flags, merchant complaints, and the retry queue while preparing a merchant-facing statement. I canceled plans with Maya, whose response helped more than I expected.",
    "mood": "stressed",
    "secondaryMood": "frustrated",
    "areas": [
      "work",
      "love"
    ],
    "tags": [
      "payouts v2",
      "workplace",
      "dating"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Priya"
      },
      {
        "kind": "person",
        "name": "Ben"
      },
      {
        "kind": "person",
        "name": "Greg"
      },
      {
        "kind": "person",
        "name": "Maya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Priya",
          "Ben",
          "Greg"
        ],
        "offset": 0,
        "summary": "I spent the day managing false duplicate flags, merchant complaints, the retry queue, and the requested merchant-facing statement while Priya recovered at home.",
        "tags": [
          "payouts v2",
          "workplace"
        ],
        "topic": "Launch fallout and clawbacks"
      },
      {
        "areasRaw": [
          "love"
        ],
        "names": [
          "Maya"
        ],
        "offset": 796,
        "summary": "I canceled plans with Maya, and her willingness to let me handle the crisis helped more than I expected.",
        "tags": [
          "dating"
        ],
        "topic": "Maya's support"
      }
    ],
    "opens": [
      {
        "about": [
          "Greg"
        ],
        "id": "t019",
        "text": "Write the merchant-facing statement without using the word bug"
      }
    ],
    "touches": [
      "t018"
    ]
  },
  {
    "date": "2025-12-11T21:15",
    "title": "Retry queue finally quiet",
    "text": "Three days after the launch, the retry queue is finally quiet, no new duplicates since midnight. Finance thinks they can recover most of the double payments by Friday, the rest go through a manual outreach process that is going to take weeks. I slept nine hours last night for the first time since Sunday and woke up feeling like I'd been hit by a bus that then backed up and hit me again. Greg sent a calendar invite for Friday titled Payouts v2 Retrospective, no agenda attached. Priya texted just the word 'fun' with no punctuation. I know exactly what that meeting is going to be.",
    "summary": "The retry queue has stabilized, but double-payment recovery will continue for weeks. I am physically exhausted and expecting Friday’s Payouts v2 retrospective to be difficult.",
    "mood": "tired",
    "secondaryMood": "stressed",
    "areas": [
      "work",
      "money"
    ],
    "tags": [
      "payouts v2",
      "workplace",
      "sleep"
    ],
    "mentions": [
      {
        "kind": "project",
        "name": "Payouts v2"
      },
      {
        "kind": "person",
        "name": "Greg"
      },
      {
        "kind": "person",
        "name": "Priya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "work",
          "money"
        ],
        "names": [
          "Payouts v2"
        ],
        "offset": 0,
        "summary": "The retry queue is quiet, and Finance expects to recover most double payments by Friday while handling the remainder through weeks of manual outreach.",
        "tags": [
          "payouts v2",
          "workplace"
        ],
        "topic": "Duplicate payment recovery"
      },
      {
        "areasRaw": [
          "health"
        ],
        "names": [],
        "offset": 243,
        "summary": "I slept longer than usual but woke up feeling physically battered.",
        "tags": [
          "sleep"
        ],
        "topic": "Exhausted after sleep"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Greg",
          "Priya",
          "Payouts v2"
        ],
        "offset": 390,
        "summary": "Greg scheduled a Payouts v2 retrospective for Friday without an agenda, and Priya’s one-word text makes the meeting feel predictably unpleasant.",
        "tags": [
          "payouts v2",
          "workplace"
        ],
        "topic": "Retrospective meeting"
      }
    ],
    "opens": [
      {
        "about": [
          "Greg",
          "Payouts v2"
        ],
        "due": "2025-12-12",
        "id": "t020",
        "text": "Attend the Payouts v2 Retrospective"
      }
    ],
    "touches": [
      "t018"
    ]
  },
  {
    "date": "2025-12-12T19:50",
    "title": "Writing the postmortem",
    "text": "Wrote the postmortem last night and didn't soften it. Said plainly that the December 9th date was moved up in October against Priya's explicit warning that the reconciliation service hadn't been load tested, that the flag in the config push should have blocked launch and didn't because nobody assigned QA to it under the compressed timeline, and that three hundred and forty merchants were double paid as a direct result. Sent it to Greg before the meeting so he wouldn't be surprised. He was not happy that it named the date as the cause. In the meeting he kept steering it toward process improvements for next time, which is a nice way of saying let's not talk about who set the date. I said the process improvement is not moving dates that engineering says aren't ready. Nobody said anything for a second. Priya looked at me like she was proud of me and terrified for me at the same time. After the meeting Greg stopped by my desk and said, very evenly, that he appreciated my candor, and then didn't say anything else to me the rest of the day. Not hostile. Just cold. Like a switch got flipped. I don't think I imagined it.",
    "summary": "I wrote and sent a direct postmortem naming the moved date, missing QA assignment, and resulting double payments. Greg reacted coldly afterward, while Priya appeared both proud of and worried about me.",
    "mood": "confident",
    "secondaryMood": "stressed",
    "areas": [
      "work"
    ],
    "tags": [
      "workplace",
      "postmortem"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Priya"
      },
      {
        "kind": "person",
        "name": "Greg"
      }
    ]
  },
  {
    "date": "2025-12-13T13:30",
    "title": "Shakshuka and a thank you",
    "text": "Slept until eleven, first time in a week. Maya showed up around one with groceries and started cooking, shakshuka, eggs poaching in the tomato sauce while she told me about a kid on her floor who named his IV pole Steve. Told her about Greg going cold on me. She said that says more about him than about you, which is the kind of thing that sounds like a fridge magnet until someone who actually means it says it to you. I should get Priya something, she carried the entire clawback effort on no sleep. Maybe a real thank you note, not just a Slack message.",
    "summary": "I caught up on sleep, spent time with Maya while she cooked, and felt supported when she responded to Greg going cold. I also want to properly thank Priya for carrying the clawback effort.",
    "mood": "grateful",
    "secondaryMood": "supported",
    "areas": [
      "friends",
      "work"
    ],
    "tags": [
      "sleep",
      "groceries",
      "gift",
      "dating"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "person",
        "name": "Greg"
      },
      {
        "kind": "person",
        "name": "Priya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "health"
        ],
        "names": [],
        "offset": 0,
        "summary": "I slept until eleven, the first time in a week.",
        "tags": [
          "sleep"
        ],
        "topic": "Catching up on sleep"
      },
      {
        "areasRaw": [
          "friends",
          "health"
        ],
        "names": [
          "Maya"
        ],
        "offset": 42,
        "summary": "I spent time with Maya while she brought groceries, cooked shakshuka, and told me a story about a kid who named his IV pole Steve.",
        "tags": [
          "groceries"
        ],
        "topic": "Maya comes over to cook"
      },
      {
        "areasRaw": [
          "friends",
          "love"
        ],
        "names": [
          "Maya",
          "Greg"
        ],
        "offset": 221,
        "summary": "I told Maya that Greg had gone cold on me, and she said it says more about him than about me.",
        "tags": [
          "dating"
        ],
        "topic": "Talking about Greg"
      },
      {
        "areasRaw": [
          "work",
          "friends"
        ],
        "names": [
          "Priya"
        ],
        "offset": 421,
        "summary": "I thought about getting Priya something and writing a real thank you note for carrying the clawback effort on no sleep.",
        "tags": [
          "gift"
        ],
        "topic": "Thanking Priya"
      }
    ],
    "opens": [
      {
        "about": [
          "Priya"
        ],
        "id": "t021",
        "text": "Get Priya something and write a real thank you note"
      }
    ]
  },
  {
    "date": "2025-12-14T19:00",
    "title": "Snow and tacos",
    "text": "Tacos with Danny, told him the whole Payouts v2 saga start to finish. He said in bartending years that's like a Saturday during a Bears loss, everybody's mad and someone's getting blamed for something that isn't really their fault. Comforting in its way. He's got a lead on a used truck for El Primo, needs somebody who knows kitchens to look at it with him. Volunteered Maya since she probably knows more about health code than either of us. Walked home in actual snow for the first time this winter, first snow always makes the city look better than it is for about a day.",
    "summary": "I had tacos with Danny, told him the Payouts v2 saga, and found his perspective comforting. He has a lead on a used truck for El Primo, I volunteered Maya to inspect it, and I walked home through the first snow of winter.",
    "mood": "supported",
    "secondaryMood": "reflective",
    "areas": [
      "friends",
      "work"
    ],
    "tags": [
      "tacos",
      "payouts v2",
      "food truck",
      "commute",
      "snow"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Danny"
      },
      {
        "kind": "project",
        "name": "Payouts v2"
      },
      {
        "kind": "project",
        "name": "El Primo"
      },
      {
        "kind": "person",
        "name": "Maya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "friends",
          "work"
        ],
        "names": [
          "Danny",
          "Payouts v2"
        ],
        "offset": 0,
        "summary": "I told Danny the full Payouts v2 story, and his comparison made the situation feel comforting in its way.",
        "tags": [
          "tacos",
          "payouts v2"
        ],
        "topic": "Payouts v2 with Danny"
      },
      {
        "areasRaw": [
          "friends",
          "work"
        ],
        "names": [
          "Danny",
          "El Primo",
          "Maya"
        ],
        "offset": 255,
        "summary": "Danny has a lead on a used truck for El Primo, and I volunteered Maya to help inspect it.",
        "tags": [
          "food truck"
        ],
        "topic": "Used truck for El Primo"
      },
      {
        "areasRaw": [
          "friends",
          "play"
        ],
        "names": [],
        "offset": 443,
        "summary": "I walked home through the first snow of winter and noticed how it briefly improved the look of the city.",
        "tags": [
          "commute"
        ],
        "topic": "First snow walk"
      }
    ],
    "opens": [
      {
        "about": [
          "Danny",
          "El Primo",
          "Maya"
        ],
        "id": "t022",
        "text": "Have Maya inspect the used truck with Danny"
      }
    ]
  },
  {
    "date": "2025-12-16T20:45",
    "title": "No heat again",
    "text": "Still no radiator. Mr. Kowalski says Thursday, which is what he said last Thursday about something else. Ordered a space heater on one day shipping because I can see my breath in the bedroom and that's not a metaphor. Pickles has claimed the one warm spot on the couch and will not be moved.",
    "summary": "I am still waiting on the bedroom radiator and ordered a one-day-shipping space heater because I can see my breath. Pickles has claimed the couch's only warm spot.",
    "mood": "frustrated",
    "secondaryMood": "stressed",
    "areas": [
      "home"
    ],
    "tags": [
      "radiator",
      "pet"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Mr. Kowalski"
      },
      {
        "kind": "other",
        "name": "Pickles"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "home"
        ],
        "names": [
          "Mr. Kowalski"
        ],
        "offset": 0,
        "summary": "I am still waiting on the bedroom radiator, so I ordered a one-day-shipping space heater because the room is dangerously cold.",
        "tags": [
          "radiator"
        ],
        "topic": "Bedroom heating delay"
      },
      {
        "areasRaw": [
          "home"
        ],
        "names": [
          "Pickles"
        ],
        "offset": 218,
        "summary": "Pickles has taken the couch's only warm spot and will not move.",
        "tags": [
          "pet"
        ],
        "topic": "Pickles and warm spot"
      }
    ],
    "touches": [
      "t017"
    ]
  },
  {
    "date": "2025-12-17T22:15",
    "title": "Trivia and a space heater",
    "text": "Trivia at The Brass Tap with Kev and Omar, Quizteama Aguilera finished second because Omar swore the capital of Australia was Sydney with total confidence. Heater arrived and actually works, bedroom is bearable again. Small victories. Kev and Jess are hosting New Year's this year, already looking forward to it.",
    "summary": "I went to trivia at The Brass Tap with Kev and Omar, where Quizteama Aguilera finished second. The heater works and the bedroom is bearable again, and I am looking forward to Kev and Jess hosting New Year's.",
    "mood": "excited",
    "secondaryMood": "content",
    "areas": [
      "friends",
      "home"
    ],
    "tags": [
      "trivia night",
      "radiator",
      "new year's"
    ],
    "mentions": [
      {
        "kind": "place",
        "name": "The Brass Tap"
      },
      {
        "kind": "person",
        "name": "Kev"
      },
      {
        "kind": "person",
        "name": "Omar"
      },
      {
        "kind": "project",
        "name": "Quizteama Aguilera"
      },
      {
        "kind": "person",
        "name": "Jess"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "friends",
          "play"
        ],
        "names": [
          "The Brass Tap",
          "Kev",
          "Omar",
          "Quizteama Aguilera"
        ],
        "offset": 0,
        "summary": "I went to trivia at The Brass Tap with Kev and Omar, and Quizteama Aguilera finished second after Omar confidently answered Sydney for Australia's capital.",
        "tags": [
          "trivia night"
        ],
        "topic": "Trivia with Kev and Omar"
      },
      {
        "areasRaw": [
          "home"
        ],
        "names": [],
        "offset": 156,
        "summary": "The heater arrived and works, making the bedroom bearable again.",
        "tags": [
          "radiator"
        ],
        "topic": "Working bedroom heater"
      },
      {
        "areasRaw": [
          "friends",
          "play"
        ],
        "names": [
          "Kev",
          "Jess"
        ],
        "offset": 235,
        "summary": "Kev and Jess are hosting New Year's this year, and I am already looking forward to it.",
        "tags": [
          "new year's"
        ],
        "topic": "New Year's hosting"
      }
    ]
  },
  {
    "date": "2025-12-19T19:30",
    "title": "What do I call this",
    "text": "It's a strange thing about dating in your thirties. Maya asked, kind of out of nowhere while we were doing dishes, what I'd call this if someone at work asked. I said girlfriend, I guess, and she said guess isn't really an answer. Fair. We didn't finish the conversation because her phone rang, a shift swap thing, but I've been thinking about it since. Six weeks in and I already know I don't want to see anyone else. Not sure why that's hard to just say out loud.",
    "summary": "I’m six weeks into dating Maya and already know I don’t want to see anyone else, but I’m having trouble saying what our relationship is out loud.",
    "mood": "uncertain",
    "secondaryMood": "reflective",
    "areas": [
      "love",
      "mind"
    ],
    "tags": [
      "dating"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      }
    ],
    "opens": [
      {
        "about": [
          "Maya"
        ],
        "id": "t023",
        "text": "Finish the conversation with Maya about what to call our relationship"
      }
    ]
  },
  {
    "date": "2025-12-20T22:50",
    "title": "Official",
    "text": "Dating for six weeks and finally told Maya tonight, actually said it without her having to drag it out of me this time. We were at her place, Pickles-less silence, just us and a bad movie neither of us was watching. I said I don't want to guess anymore either, I want to just say it, you're my girlfriend and I'm your boyfriend and that's the thing now. She laughed at how formal I made it sound and then kissed me and said finally. Six weeks of dinners and night shift texts at two in the morning and now it has a name. Feels stupid how much lighter that made me. We ordered pho even though it was ten at night because neither of us wanted to cook, ate it on her couch, and I kept looking over at her like an idiot. Danny is going to make fun of me for how happy I sound. Worth it.",
    "summary": "I told Maya that we are officially boyfriend and girlfriend, and she kissed me and said finally. I felt much lighter and happy afterward while we ate pho together.",
    "mood": "joyful",
    "secondaryMood": "relieved",
    "areas": [
      "love"
    ],
    "tags": [
      "dating",
      "dinner",
      "late night"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "other",
        "name": "Pickles"
      },
      {
        "kind": "person",
        "name": "Danny"
      }
    ],
    "resolves": [
      "t023"
    ]
  },
  {
    "date": "2025-12-22T18:15",
    "title": "Wrapping up before break",
    "text": "Last real work day before the holiday break. Gave Priya a card and a bottle of the mezcal she mentioned liking once in March, felt small compared to what she did for the team but she seemed genuinely touched. Also finally got Nina's gift sorted, the soup subscription, wrapped and shipped before I could talk myself out of something more complicated and worse. Office was half empty by three, everyone checked out early. Greg said happy holidays to me in the hallway like nothing happened between us. I said the same back. We're going to be doing this dance for a while I think.",
    "summary": "I gave Priya a thoughtful card and mezcal, shipped Nina's gift, and finished the last work day before the break. Greg and I exchanged polite holiday greetings despite what happened between us.",
    "mood": "conflicted",
    "secondaryMood": "grateful",
    "areas": [
      "work"
    ],
    "tags": [
      "gift",
      "workplace"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Priya"
      },
      {
        "kind": "person",
        "name": "Nina"
      },
      {
        "kind": "person",
        "name": "Greg"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Priya"
        ],
        "offset": 45,
        "summary": "I gave Priya a card and mezcal, and she seemed genuinely touched.",
        "tags": [
          "gift",
          "workplace"
        ],
        "topic": "Priya's thank-you gift"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Nina"
        ],
        "offset": 209,
        "summary": "I wrapped and shipped Nina's soup subscription before overcomplicating the gift.",
        "tags": [
          "gift"
        ],
        "topic": "Nina's gift"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Greg"
        ],
        "offset": 361,
        "summary": "The office emptied early, and I exchanged a strained holiday greeting with Greg.",
        "tags": [
          "workplace"
        ],
        "topic": "Holiday office atmosphere"
      }
    ],
    "resolves": [
      "t021"
    ]
  },
  {
    "date": "2025-12-23T20:40",
    "title": "Packing for Naperville",
    "text": "Packing for Naperville tomorrow. Maya's coming for real this time, meeting everyone properly, not just a name Abuela asks about. Told Mom she's vegetarian-adjacent and Mom said that's fine, more tamales for everyone else, which is not really engaging with the information but that's Mom. Nervous in a way I wasn't expecting. Pickles is staying with the downstairs neighbor for two days and already hates me for the carrier coming out.",
    "summary": "I am packing for a family visit to Naperville where Maya will meet everyone properly, and I am more nervous than expected. Pickles will stay with the downstairs neighbor for two days and already resents the carrier.",
    "mood": "anxious",
    "secondaryMood": "connected",
    "areas": [
      "family",
      "home"
    ],
    "tags": [
      "family news",
      "pet"
    ],
    "mentions": [
      {
        "kind": "place",
        "name": "Naperville"
      },
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "person",
        "name": "Abuela"
      },
      {
        "kind": "person",
        "name": "Mom"
      },
      {
        "kind": "other",
        "name": "Pickles"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "family"
        ],
        "names": [
          "Naperville",
          "Maya",
          "Abuela",
          "Mom"
        ],
        "offset": 0,
        "summary": "I am packing for Maya to meet my family properly in Naperville, while feeling unexpectedly nervous about it.",
        "tags": [
          "family news"
        ],
        "topic": "Maya meets my family"
      },
      {
        "areasRaw": [
          "home"
        ],
        "names": [
          "Pickles"
        ],
        "offset": 325,
        "summary": "I am leaving Pickles with the downstairs neighbor for two days, and Pickles already dislikes the carrier.",
        "tags": [
          "pet"
        ],
        "topic": "Pickles's temporary stay"
      }
    ],
    "resolves": [
      "t014"
    ]
  },
  {
    "date": "2025-12-24T23:30",
    "title": "Christmas Eve tamales",
    "text": "Christmas Eve in Naperville and it went better than I let myself hope for. Abuela pulled Maya into the kitchen within about four minutes of us walking in the door and had her folding masa into corn husks by the time I found them, laughing about something in Spanish faster than Maya could follow, but she was following the folding fine, better than I ever have honestly. Mom kept finding reasons to walk through the kitchen and each time left looking a little more delighted. Dad didn't say much, he never does, but he made a point of getting Maya a beer without being asked and sat next to her at dinner instead of his usual spot, which from Dad is basically a toast. Nina cornered me by the stairs and said, quietly, she's good for you, don't mess it up, which from Nina is basically a hug. Leo made Maya watch him do a dinosaur roar approximately eleven times and she gave each one a genuine rating. Tommy showed up late from a friend's, ate four tamales standing at the counter, asked Maya if she'd ever seen someone die at work and then immediately apologized, which Maya thought was funnier than offensive. Drove home at midnight with tamales in a container on Maya's lap, radio low, both of us quiet in the good way. She said your family is loud in the nicest way I've ever seen loud be. I think that's the whole thing right there.",
    "summary": "I spent Christmas Eve with Maya and my family in Naperville, and her warm, funny connection with everyone went better than I had hoped. Driving home together, I felt that her description of my family captured the whole evening.",
    "mood": "connected",
    "secondaryMood": "loved",
    "areas": [
      "family",
      "love"
    ],
    "tags": [
      "family news",
      "dating",
      "christmas eve",
      "tamales"
    ],
    "mentions": [
      {
        "kind": "event",
        "name": "Christmas Eve"
      },
      {
        "kind": "place",
        "name": "Naperville"
      },
      {
        "kind": "person",
        "name": "Abuela"
      },
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "person",
        "name": "Mom"
      },
      {
        "kind": "person",
        "name": "Dad"
      },
      {
        "kind": "person",
        "name": "Nina"
      },
      {
        "kind": "person",
        "name": "Leo"
      },
      {
        "kind": "person",
        "name": "Tommy"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "family",
          "love"
        ],
        "names": [
          "Christmas Eve",
          "Naperville",
          "Abuela",
          "Maya",
          "Mom",
          "Dad",
          "Nina",
          "Leo"
        ],
        "offset": 0,
        "summary": "I brought Maya into my family’s Christmas Eve, and everyone welcomed her in their own way.",
        "tags": [
          "family news",
          "christmas eve"
        ],
        "topic": "Family Christmas Eve"
      },
      {
        "areasRaw": [
          "love"
        ],
        "names": [
          "Maya"
        ],
        "offset": 1113,
        "summary": "I drove home quietly with Maya and felt that her connection with my family captured what mattered about the evening.",
        "tags": [
          "dating",
          "tamales"
        ],
        "topic": "Drive home with Maya"
      }
    ]
  },
  {
    "date": "2025-12-25T11:30",
    "title": "Quiet Christmas Day",
    "text": "Christmas Day was mercifully low key, still at Mom and Dad's, everyone moving slow after last night. Maya and Abuela were back at it this morning like old friends, going through Abuela's recipe box, actual index cards in handwriting from decades ago. Ava fell asleep under the tree at one point and nobody moved her for an hour. Drove back to the city in the afternoon, quiet drive, good kind of tired.",
    "summary": "I had a low-key Christmas Day at Mom and Dad's with family, including a quiet morning with old recipe cards and Ava sleeping under the tree. I drove back to the city feeling pleasantly tired.",
    "mood": "calm",
    "secondaryMood": "connected",
    "areas": [
      "family",
      "play"
    ],
    "tags": [
      "christmas",
      "family gathering",
      "recipe box",
      "drive",
      "quiet evening"
    ],
    "mentions": [
      {
        "kind": "event",
        "name": "Christmas Day"
      },
      {
        "kind": "person",
        "name": "Mom"
      },
      {
        "kind": "person",
        "name": "Dad"
      },
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "person",
        "name": "Abuela"
      },
      {
        "kind": "person",
        "name": "Ava"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "family"
        ],
        "names": [
          "Christmas Day",
          "Mom",
          "Dad",
          "Maya",
          "Abuela",
          "Ava"
        ],
        "offset": 0,
        "summary": "I spent a slow, low-key Christmas morning at Mom and Dad's with family, including Maya and Abuela looking through old recipe cards and Ava sleeping under the tree.",
        "tags": [
          "christmas",
          "family gathering",
          "recipe box"
        ],
        "topic": "Christmas morning with family"
      },
      {
        "areasRaw": [
          "play"
        ],
        "names": [],
        "offset": 329,
        "summary": "I drove back to the city in the afternoon and felt quietly, pleasantly tired.",
        "tags": [
          "drive",
          "quiet evening"
        ],
        "topic": "Quiet drive back"
      },
      {
        "areasRaw": [
          "family",
          "play"
        ],
        "names": [
          "Christmas Day",
          "Mom",
          "Dad",
          "Maya",
          "Abuela",
          "Ava"
        ],
        "summary": "I had a calm, connected Christmas Day with family, followed by a quiet drive back to the city and a good kind of tired.",
        "tags": [
          "christmas",
          "family gathering",
          "recipe box",
          "drive"
        ],
        "topic": "Christmas Day and drive back"
      }
    ]
  },
  {
    "date": "2025-12-27T15:30",
    "title": "Back to the apartment",
    "text": "Back in the apartment, back to normal chaos. Pickles greeted me by knocking a mug off the counter within ninety seconds of the carrier door opening, so, missed me too buddy. Did three loads of laundry I'd been avoiding since before Naperville. Found Maya's phone charger tangled in my sheets, she must have left it last time she stayed over, need to remember to bring it to her before her old one dies completely. Quiet day, good for once. Watched most of a documentary about competitive cheese rolling that made no sense and I loved it.",
    "summary": "I returned to the apartment, handled neglected laundry, and found Maya's phone charger to return to her. I enjoyed a quiet day and a strange documentary about competitive cheese rolling.",
    "mood": "content",
    "secondaryMood": "joyful",
    "areas": [
      "home",
      "play"
    ],
    "tags": [
      "pet",
      "laundry",
      "quiet evening",
      "documentary",
      "texting"
    ],
    "mentions": [
      {
        "kind": "other",
        "name": "Pickles"
      },
      {
        "kind": "place",
        "name": "Naperville"
      },
      {
        "kind": "person",
        "name": "Maya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "home"
        ],
        "names": [
          "Pickles"
        ],
        "offset": 0,
        "summary": "I returned to apartment chaos and Pickles greeted me by knocking a mug off the counter.",
        "tags": [
          "pet"
        ],
        "topic": "Apartment and Pickles"
      },
      {
        "areasRaw": [
          "home"
        ],
        "names": [
          "Naperville",
          "Maya"
        ],
        "offset": 174,
        "summary": "I caught up on laundry and found Maya's phone charger tangled in my sheets, leaving it open to return to her.",
        "tags": [
          "laundry",
          "texting"
        ],
        "topic": "Laundry and charger"
      },
      {
        "areasRaw": [
          "play"
        ],
        "names": [],
        "offset": 414,
        "summary": "I watched most of a documentary about competitive cheese rolling and loved its absurdity.",
        "tags": [
          "quiet evening",
          "documentary"
        ],
        "topic": "Cheese rolling documentary"
      }
    ],
    "opens": [
      {
        "about": [
          "Maya"
        ],
        "id": "t024",
        "text": "Bring Maya's phone charger to her"
      }
    ]
  },
  {
    "date": "2025-12-31T23:55",
    "title": "New Year's Eve steps",
    "text": "Dating someone on night shifts means holidays land wherever her schedule allows, and this year that meant New Year's Eve at Kev and Jess's, low key by their standards now that Jess is very pregnant and tired by nine most nights, but she made it to midnight on ginger ale and sheer will. Maya came straight from a shift, still a little wired the way she gets after twelve hours on the floor, and somewhere around eleven thirty, sitting on Kev's back steps in the cold because inside got too loud, she said it. Just said, I love you, easy, like she'd been carrying it around and finally set it down. I didn't say it back. I said something like I really care about you, which even as it left my mouth I could hear how it landed wrong, how it sounded like a hedge. She said it's okay, take your time, and meant it, I think, but I saw something close in her face a little. We watched the ball drop on Kev's phone because his TV cable was out, all four of us packed on the back steps counting down badly, out of sync with the actual countdown by about four seconds. Kissed her at midnight. Didn't say it. Drove home mostly quiet, replaying it, hating myself a little for not just saying the true thing when she handed it to me for free.",
    "summary": "I spent New Year's Eve with Maya at Kev and Jess's, where Maya told me she loves me. I told her I care about her instead, then replayed the moment on the drive home and regretted not saying what I feel.",
    "mood": "conflicted",
    "secondaryMood": "guilty",
    "areas": [
      "love",
      "friends"
    ],
    "tags": [
      "dating",
      "new year's"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Kev"
      },
      {
        "kind": "person",
        "name": "Jess"
      },
      {
        "kind": "person",
        "name": "Maya"
      }
    ]
  },
  {
    "date": "2026-01-01T10:30",
    "title": "New Year hangover",
    "text": "New Year's Day, head a little foggy, replaying last night on a loop. Called Danny around noon because he's the only one who won't tell me what I want to hear. Told him what happened on the steps. He was quiet for a second and then said, you know you love her, right, like it wasn't even a question, so what's actually stopping you from saying it. I didn't have a good answer. Something about the last time I said it first to someone, back in college, and how it didn't end anywhere good. Danny said that was a different person and a different decade, man. He's right. Doesn't make the words easier to get out. This is what dating at thirty one does to you, apparently.",
    "summary": "I replayed last night and talked with Danny about loving her and what is stopping me from saying it. I connected my hesitation to a painful experience from college, even while recognizing that this is a different person and a different decade.",
    "mood": "reflective",
    "secondaryMood": "conflicted",
    "areas": [
      "love",
      "mind"
    ],
    "tags": [
      "dating"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Danny"
      }
    ],
    "opens": [
      {
        "id": "t025",
        "text": "Decide whether to tell her I love her"
      }
    ]
  },
  {
    "date": "2026-01-03T21:30",
    "title": "Saying it back",
    "text": "Said it. Saturday morning, both of us still in bed, sun barely up, Maya half asleep against my shoulder, and I just said it, I love you, no lead up, no big moment, just true and out loud before I could talk myself out of it again. She opened one eye and said finally, you goon, and pulled me back down like we hadn't just had a small earthquake happen. Told her about the college thing after, why I froze on the steps, and she just listened, didn't make it a bigger deal than it was. Dating someone who just waits you out instead of pushing, turns out that's the whole trick. Made pancakes badly together, burned the first two, ate them anyway. Best terrible pancakes of my life.",
    "summary": "I told Maya I love her, and she responded warmly and patiently. We made and ate badly burned pancakes together.",
    "mood": "loved",
    "secondaryMood": "connected",
    "areas": [
      "love",
      "play"
    ],
    "tags": [
      "dating",
      "pancakes"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "love"
        ],
        "names": [
          "Maya"
        ],
        "offset": 0,
        "summary": "I told Maya I love her, and she responded warmly while listening to why I had frozen before.",
        "tags": [
          "dating"
        ],
        "topic": "Saying I love you"
      },
      {
        "areasRaw": [
          "play"
        ],
        "names": [],
        "offset": 576,
        "summary": "I made pancakes with Maya, burned the first two, and ate them anyway.",
        "tags": [
          "pancakes"
        ],
        "topic": "Burned pancakes"
      }
    ],
    "resolves": [
      "t025"
    ]
  },
  {
    "date": "2026-01-05T18:45",
    "title": "Charger drop off",
    "text": "Back to work Monday, everyone dragging. Dropped Maya's charger off at her place on my way, she was heading out for a shift and gave me a two second kiss goodbye that somehow made the whole gray Monday better. Greg still weirdly formal with me since the postmortem, three word answers in standup. Whatever. Not my circus today.",
    "summary": "I went back to work on a gray Monday and dropped Maya's charger off on the way. Her two-second kiss goodbye made the day better, while Greg stayed weirdly formal after the postmortem.",
    "mood": "loved",
    "secondaryMood": "irritated",
    "areas": [
      "work",
      "love"
    ],
    "tags": [
      "workplace",
      "dating",
      "postmortem",
      "gift"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "person",
        "name": "Greg"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "work"
        ],
        "names": [],
        "offset": 0,
        "summary": "I went back to work on a gray Monday with everyone dragging.",
        "tags": [
          "workplace"
        ],
        "topic": "Back to work"
      },
      {
        "areasRaw": [
          "love"
        ],
        "names": [
          "Maya"
        ],
        "offset": 40,
        "summary": "I dropped off Maya's charger, and her two-second kiss goodbye made the whole gray Monday better.",
        "tags": [
          "dating",
          "gift"
        ],
        "topic": "Maya's goodbye"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Greg"
        ],
        "offset": 209,
        "summary": "Greg remained weirdly formal with me after the postmortem, giving three-word answers in standup.",
        "tags": [
          "workplace",
          "postmortem"
        ],
        "topic": "Greg at standup"
      }
    ]
  },
  {
    "date": "2026-01-06T17:20",
    "title": "Radiator finally fixed",
    "text": "Mr. Kowalski's guy finally came and fixed the radiator, three weeks and two days after it died, new part, no charge since it's obviously on him. Bedroom is warm for the first time since before Christmas. Small thing. Felt disproportionately great.",
    "summary": "Mr. Kowalski's guy fixed my bedroom radiator with a new part at no charge. My bedroom is warm again, and it felt disproportionately great.",
    "mood": "relieved",
    "secondaryMood": "joyful",
    "areas": [
      "home"
    ],
    "tags": [
      "radiator"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Mr. Kowalski"
      }
    ],
    "resolves": [
      "t017"
    ]
  },
  {
    "date": "2026-01-07T20:50",
    "title": "The performance conversation",
    "text": "Greg pulled me into a conference room at four with no warning, HR language already loaded, said this was a check in about performance following the launch incident. Incident. Like Payouts v2 was weather. He said leadership had concerns about judgment under pressure and about how the postmortem was received by stakeholders, which is a very careful way of saying he didn't like being named. Said he wanted to see improvement over the next month. I asked what specifically that meant, what improvement looks like, and he got vague, said things like alignment and communication style. I said I'd like that in writing since vague feedback is hard to act on. He said he'd send a summary. He has not sent a summary. Sat in my car in the parking garage for ten minutes after, not driving anywhere, just sitting there doing math on how much of this is real performance concern and how much is a guy who got called out publicly finding a legal way to be petty about it. Didn't tell Maya right away. Needed to sit with it first.",
    "summary": "Greg gave me vague performance feedback tied to the Payouts v2 launch incident, including concerns about judgment and communication, and said he would send a written summary that has not arrived. I spent time weighing the substance of the criticism against the possibility that he was reacting to being named in the postmortem.",
    "mood": "frustrated",
    "secondaryMood": "anxious",
    "areas": [
      "work",
      "mind"
    ],
    "tags": [
      "workplace",
      "postmortem",
      "performance feedback",
      "processing"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Greg"
      },
      {
        "kind": "project",
        "name": "Payouts v2"
      },
      {
        "kind": "person",
        "name": "Maya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Greg",
          "Payouts v2"
        ],
        "offset": 0,
        "summary": "Greg gave me vague performance feedback after the Payouts v2 launch incident and said he would send a written summary.",
        "tags": [
          "workplace",
          "postmortem",
          "performance feedback"
        ],
        "topic": "Performance feedback meeting"
      },
      {
        "areasRaw": [
          "mind",
          "work"
        ],
        "names": [
          "Maya"
        ],
        "summary": "I sat in the parking garage trying to assess whether the feedback reflected real performance concerns or personal retaliation, and did not tell Maya immediately.",
        "tags": [
          "workplace",
          "processing"
        ],
        "topic": "After the meeting"
      }
    ],
    "opens": [
      {
        "about": [
          "Greg"
        ],
        "id": "t026",
        "text": "Waiting for Greg to send the performance feedback summary in writing."
      }
    ]
  },
  {
    "date": "2026-01-09T21:30",
    "title": "Telling Maya about Greg",
    "text": "Told Maya about the performance conversation over dinner, the whole thing, the vague improvement language, the sitting in the parking garage. She got quiet and then said that sounds like someone building a file, not someone trying to help you get better. I hadn't wanted to say that word out loud, file, like a legal document with my name on it, but once she said it I couldn't unhear it. She asked if I'd talked to anyone else at work about it. Just Priya, briefly, and Priya's read was similar, she said watch your back. Two people I trust both landed in the same bad place independently. That tells me something.",
    "summary": "I told Maya and Priya about the performance conversation, and both independently read it as someone building a file rather than helping me improve.",
    "mood": "anxious",
    "secondaryMood": "reflective",
    "areas": [
      "work"
    ],
    "tags": [
      "performance feedback",
      "processing"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "person",
        "name": "Priya"
      }
    ]
  },
  {
    "date": "2026-01-13T22:00",
    "title": "Denise added to the invite",
    "text": "Calendar invite from Greg for tomorrow at three, no agenda, just my name and Denise's from HR added as an attendee. Denise doesn't sit in on performance check ins. I know what this is before it happens. Told nobody. Slept maybe two hours.",
    "summary": "I received a calendar invite from Greg for tomorrow at three with Denise from HR, despite her not sitting in on performance check-ins. I am certain I know what the meeting is about, have told nobody, and slept about two hours.",
    "mood": "anxious",
    "secondaryMood": "tired",
    "areas": [
      "work",
      "health"
    ],
    "tags": [
      "workplace",
      "sleep"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Greg"
      },
      {
        "kind": "person",
        "name": "Denise"
      },
      {
        "kind": "organization",
        "name": "HR"
      }
    ]
  },
  {
    "date": "2026-01-14T15:30",
    "title": "Fired",
    "text": "Fired today. Three o'clock, conference room, Greg reading from a paper like he needed the paper to remember my name, Denise next to him with the folder already prepared, severance letter and everything, which means this was decided before I walked in, maybe before Friday even. Greg said the word restructuring. Then he said performance. He used both, which even in the moment I noticed was inconsistent, pick one. Denise walked me through six weeks of severance, COBRA information, a laptop return checklist like I was a piece of hardware being decommissioned. I asked if this was about the Payouts v2 launch and Greg said this isn't about any one thing, which is what people say when it is definitely about one thing. Packed my desk into a cardboard box someone had ready and waiting, which means they knew, everyone probably knew before I did. Priya found me in the elevator lobby, hugged me without saying anything for a second, then said this is not okay and I am going to stay in touch, actually stay in touch, not the fake kind. Ben looked like he wanted to say something and didn't, which I understood, he's twenty six and scared for his own job probably. Walked out of the building I've gone into almost every weekday for three years carrying a box with a desk plant and a mug that says World's Okayest PM that Kev got me as a joke two Christmases ago. Sat in my car in the same parking garage as last week and didn't do math this time, just sat there. Called Maya. She picked up on the first ring like she'd been holding her phone.",
    "summary": "I was fired after a prepared meeting with Greg and Denise, then left the workplace with my belongings. Priya offered sincere support, I sat in my car without doing the usual math, and Maya answered immediately when I called.",
    "mood": "hurt",
    "secondaryMood": "angry",
    "areas": [
      "work"
    ],
    "tags": [
      "workplace",
      "processing",
      "payouts v2",
      "performance feedback",
      "texting"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Greg"
      },
      {
        "kind": "person",
        "name": "Denise"
      },
      {
        "kind": "project",
        "name": "Payouts v2"
      },
      {
        "kind": "person",
        "name": "Priya"
      },
      {
        "kind": "person",
        "name": "Ben"
      },
      {
        "kind": "person",
        "name": "Kev"
      },
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "other",
        "name": "COBRA"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Greg",
          "Denise",
          "Payouts v2"
        ],
        "offset": 0,
        "summary": "I was fired in a prepared meeting where Greg and Denise cited both restructuring and performance, provided severance and COBRA information, and connected the decision to the Payouts v2 launch without acknowledging it directly.",
        "tags": [
          "workplace",
          "payouts v2",
          "performance feedback"
        ],
        "topic": "termination meeting"
      },
      {
        "areasRaw": [
          "work",
          "friends"
        ],
        "names": [
          "Priya",
          "Ben"
        ],
        "offset": 847,
        "summary": "I received genuine support from Priya while Ben appeared too afraid to speak.",
        "tags": [
          "workplace",
          "processing"
        ],
        "topic": "colleague reactions"
      },
      {
        "areasRaw": [
          "work",
          "mind"
        ],
        "names": [
          "Kev"
        ],
        "offset": 1164,
        "summary": "I left after three years carrying my desk belongings, then sat in my car without doing the usual math.",
        "tags": [
          "workplace",
          "processing"
        ],
        "topic": "leaving the workplace"
      },
      {
        "areasRaw": [
          "friends"
        ],
        "names": [
          "Maya"
        ],
        "offset": 1462,
        "summary": "I called Maya, and she answered immediately as if she had been waiting for me.",
        "tags": [
          "texting"
        ],
        "topic": "calling Maya"
      }
    ]
  },
  {
    "date": "2026-01-14T21:00",
    "title": "Pho on the couch",
    "text": "Maya showed up two hours after I called her with a bag from Little Saigon Pho, the good broth, extra basil, didn't ask me to talk about it until I'd eaten most of the bowl. Then she just sat with me on the couch while I said all of it out loud again, the paper Greg read from, the box, Priya in the elevator lobby. She didn't try to fix it or find the silver lining, just kept saying I'm right here, over and over, which turned out to be exactly the right thing to say. Pickles curled up on my lap and didn't move for two hours either, like he knew. I don't know what I did to deserve either of them tonight.",
    "summary": "I was supported by Maya and Pickles tonight as I talked through what happened, and I felt grateful for their presence and care.",
    "mood": "supported",
    "secondaryMood": "grateful",
    "areas": [
      "friends"
    ],
    "tags": [
      "processing",
      "pet"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "place",
        "name": "Little Saigon Pho"
      },
      {
        "kind": "person",
        "name": "Greg"
      },
      {
        "kind": "person",
        "name": "Priya"
      },
      {
        "kind": "other",
        "name": "Pickles"
      }
    ]
  },
  {
    "date": "2026-01-15T11:45",
    "title": "Rebuilding the resume",
    "text": "Woke up and for about four seconds forgot, then remembered. That's going to happen for a while probably. Opened my resume for the first time in three years and it is embarrassing, still lists a job I had in 2019. Need to actually rebuild it properly before I send it anywhere, not just patch the dates. Called the unemployment office, was on hold for forty minutes, got disconnected, will try again tomorrow. One thing at a time.",
    "summary": "I briefly forgot and then remembered, opened my outdated resume, and realized I need to rebuild it properly before sending it anywhere. I was disconnected after forty minutes on hold with the unemployment office and will try again tomorrow.",
    "mood": "stressed",
    "secondaryMood": "ashamed",
    "areas": [
      "work",
      "money"
    ],
    "tags": [
      "workplace",
      "processing"
    ],
    "mentions": [],
    "sections": [
      {
        "areasRaw": [
          "mind"
        ],
        "names": [],
        "offset": 0,
        "summary": "I briefly forgot and then remembered, expecting that to happen for a while.",
        "tags": [
          "processing"
        ],
        "topic": "Waking and remembering"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [],
        "offset": 105,
        "summary": "I saw that my resume is outdated and embarrassing, and need to rebuild it properly before sending it anywhere.",
        "tags": [
          "workplace"
        ],
        "topic": "Resume rebuild"
      },
      {
        "areasRaw": [
          "money",
          "work"
        ],
        "names": [],
        "offset": 303,
        "summary": "I spent forty minutes on hold, was disconnected, and plan to try again tomorrow.",
        "tags": [
          "workplace"
        ],
        "topic": "Unemployment office"
      },
      {
        "areasRaw": [
          "mind"
        ],
        "names": [],
        "offset": 409,
        "summary": "I am taking the situation one thing at a time.",
        "tags": [
          "processing"
        ],
        "topic": "Taking things gradually"
      }
    ],
    "opens": [
      {
        "id": "t027",
        "text": "Rebuild my resume properly before sending it anywhere"
      },
      {
        "due": "2026-01-16",
        "id": "t028",
        "text": "Try calling the unemployment office again"
      }
    ]
  },
  {
    "date": "2026-01-16T18:30",
    "title": "Telling Dad",
    "text": "Drove out to Naperville to tell Dad in person before he heard it secondhand from Mom who heard it from Nina who I'd already told on the phone, small family, bad telephone game. Told him at the kitchen table, plain, got fired, severance, going to be fine financially for a while. Dad didn't say much, which from him usually means he's working something out internally before he speaks. Finally he said, you'll find something, you're good at what you do, this guy Greg sounds like a jerk. Coming from Dad, jerk is close to a curse word. Then he got quiet again and I could tell he was thinking about his own layoff years ago, the electrician job that folded when I was a kid, how long it took him to find steady work again. He didn't say any of that out loud. Didn't need to. Hugged him on the way out, which we don't really do, and he let it go a beat longer than usual.",
    "summary": "I drove to Naperville to tell Dad in person that I was fired and had severance, and he told me I would find something and was good at what I do. We shared an unusually long hug after talking about the layoff and what it brought back for him.",
    "mood": "supported",
    "secondaryMood": "connected",
    "areas": [
      "family",
      "work"
    ],
    "tags": [
      "family news",
      "workplace"
    ],
    "mentions": [
      {
        "kind": "place",
        "name": "Naperville"
      },
      {
        "kind": "person",
        "name": "Dad"
      },
      {
        "kind": "person",
        "name": "Mom"
      },
      {
        "kind": "person",
        "name": "Nina"
      },
      {
        "kind": "person",
        "name": "Greg"
      }
    ]
  },
  {
    "date": "2026-01-18T16:00",
    "title": "Nina and Maya both say it",
    "text": "Nina called, blunt as always, said losing the job isn't the thing I should be worried about, it's how I get quiet and disappear into my own head when things go bad, she's watched me do it since we were kids. Said flatly, you should try therapy, an actual professional, not just Danny and a six pack. Maya said almost the same thing an hour later like they'd coordinated it, which they hadn't, she said she's noticed me going somewhere else in my head lately even before the firing. I got a little defensive, said I'm handling it fine. Neither of them looked convinced. Honestly neither am I.",
    "summary": "Nina and Maya both told me they’ve noticed me getting quiet and disappearing into my own head, especially around the firing. I said I’m handling it fine, but honestly neither they nor I seem convinced.",
    "mood": "uncertain",
    "secondaryMood": "anxious",
    "areas": [
      "mind",
      "work"
    ],
    "tags": [
      "processing",
      "workplace"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Nina"
      },
      {
        "kind": "person",
        "name": "Danny"
      },
      {
        "kind": "person",
        "name": "Maya"
      }
    ]
  },
  {
    "date": "2026-01-24T11:00",
    "title": "Resume done, Café Olmo",
    "text": "Finally rebuilt the resume top to bottom, took an entire Saturday, but it's done and it actually reads like something someone would call back for. Started working out of Café Olmo this week since sitting alone in the apartment all day was making me stir crazy, the guy behind the counter already knows my order, a small thing that helps more than it should. Applied to six places today. Budget spreadsheet says the severance plus savings gets me to about June if I'm careful. If. Going to be careful.",
    "summary": "I finished rebuilding my resume, started working from Café Olmo, and applied to six places. My severance and savings could last until June if I am careful.",
    "mood": "proud",
    "secondaryMood": "anxious",
    "areas": [
      "work",
      "money"
    ],
    "tags": [
      "workplace",
      "coffee",
      "resume",
      "job search",
      "budgeting",
      "severance"
    ],
    "mentions": [
      {
        "kind": "place",
        "name": "Café Olmo"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "work"
        ],
        "names": [],
        "offset": 0,
        "summary": "I rebuilt my resume from top to bottom and finished with a version I believe could get callbacks.",
        "tags": [
          "workplace",
          "resume"
        ],
        "topic": "Resume rebuild"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Café Olmo"
        ],
        "offset": 147,
        "summary": "I started working from Café Olmo to avoid feeling stir crazy alone in my apartment, and the familiar order there helps.",
        "tags": [
          "workplace",
          "coffee"
        ],
        "topic": "Café Olmo work routine"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [],
        "offset": 358,
        "summary": "I applied to six places today.",
        "tags": [
          "workplace",
          "job search"
        ],
        "topic": "Job applications"
      },
      {
        "areasRaw": [
          "money"
        ],
        "names": [],
        "offset": 387,
        "summary": "I calculated that my severance and savings could last until about June if I stay careful with money.",
        "tags": [
          "budgeting",
          "severance"
        ],
        "topic": "Savings runway"
      }
    ],
    "resolves": [
      "t027"
    ]
  },
  {
    "date": "2026-01-26T13:30",
    "title": "First Canopy Health round",
    "text": "First real interview since getting fired, a product manager role at Canopy Health, video call from Café Olmo with headphones on so the espresso machine wouldn't ruin it. Went fine I think, maybe better than fine, the hiring manager seemed to actually light up when I talked about the reconciliation disaster and how I handled the postmortem, which is a strange thing to be selling as a strength but here we are. Second round scheduled for next week if this goes well. First time in two weeks I've felt like a person with a future instead of a guy with a box of desk stuff in his closet.",
    "summary": "I had my first real interview since getting fired for a product manager role at Canopy Health. It went well enough that I have a possible second round next week, and I felt hopeful about having a future again.",
    "mood": "hopeful",
    "secondaryMood": "confident",
    "areas": [
      "work",
      "mind"
    ],
    "tags": [
      "workplace",
      "job search",
      "postmortem"
    ],
    "mentions": [
      {
        "kind": "organization",
        "name": "Canopy Health"
      },
      {
        "kind": "place",
        "name": "Café Olmo"
      }
    ]
  },
  {
    "date": "2026-01-29T19:15",
    "title": "First session with Dr. Adler",
    "text": "First session with Dr. Adler today, six o'clock, a small office above a dry cleaner that did not look like what I pictured. Went in expecting to talk about the firing and mostly ended up talking about my dad instead, which surprised me, I don't know how we got there. Dr. Adler didn't do the thing I was braced for, the nodding and mm-hmm and here's how that makes you feel. Mostly just asked plain questions. What do you actually want right now, not what do you think you should want. I didn't have a clean answer. Told him I've been skeptical about this whole thing, therapy, that it feels like paying someone to listen to me complain. He said that's a fair thing to be skeptical about and we'll find out together if it's true. Fifty minutes went by fast, faster than I expected. Walked out into the cold feeling strange, not lighter exactly, more like something got stirred up that used to sit still. A hundred and eighty dollars for that, partly out of pocket now with no work insurance. Going back Thursday anyway.",
    "summary": "I had my first session with Dr. Adler and ended up talking more about my dad than the firing. I remain skeptical about therapy, but I am going back Thursday after leaving feeling like something had been stirred up.",
    "mood": "reflective",
    "secondaryMood": "uncertain",
    "areas": [
      "mind",
      "money"
    ],
    "tags": [
      "processing",
      "therapy"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Dr. Adler"
      }
    ],
    "opens": [
      {
        "about": [
          "Dr. Adler"
        ],
        "id": "t029",
        "text": "Go back to therapy Thursday"
      }
    ]
  },
  {
    "date": "2026-02-01T17:30",
    "title": "Tacos and budget math",
    "text": "Tacos with Danny, told him the actual numbers, severance running down faster than I want to admit because COBRA alone is eating a chunk of it every month. He didn't try to fix it, just said El Primo's going to need someone who can read a spreadsheet once the loan comes through, keep that in your back pocket. Half joke, half not. Walked home past the closed farmers market lot thinking about money more than I have in years, actually doing math in my head at the taco counter like some kind of stress reflex now.",
    "summary": "I told Danny how quickly my severance is running down, with COBRA taking a large monthly share, and he mentioned a possible spreadsheet role with El Primo. I walked home thinking about money and doing mental math as a stress reflex.",
    "mood": "stressed",
    "secondaryMood": "reflective",
    "areas": [
      "money",
      "friends"
    ],
    "tags": [
      "tacos",
      "severance",
      "budgeting"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Danny"
      },
      {
        "kind": "other",
        "name": "COBRA"
      },
      {
        "kind": "project",
        "name": "El Primo"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "money",
          "friends"
        ],
        "names": [
          "Danny",
          "COBRA",
          "El Primo"
        ],
        "offset": 0,
        "summary": "I told Danny the actual numbers, and he mentioned a possible spreadsheet role with El Primo once the loan comes through.",
        "tags": [
          "tacos",
          "severance",
          "budgeting"
        ],
        "topic": "Tacos with Danny"
      },
      {
        "areasRaw": [
          "money"
        ],
        "names": [],
        "offset": 331,
        "summary": "I thought about money intensely and noticed myself doing math as a stress reflex.",
        "tags": [
          "budgeting",
          "severance"
        ],
        "topic": "Walking and money"
      }
    ]
  },
  {
    "date": "2026-02-04T20:30",
    "title": "Second Canopy Health round",
    "text": "Second interview round with Canopy Health, three people this time on the call instead of one, felt more like a defense than a conversation. One of them asked how I'd handle a launch date being moved up against engineering's objection, which felt like a very specific question for them to ask a guy who just got fired for exactly that. Answered honestly, said I'd document the risk in writing and escalate above the person moving it if needed, which is exactly what I didn't do enough of at Ledgerline. They said they'd be in touch by end of week. Trying not to obsess over the phrasing of that.",
    "summary": "I had a second interview with Canopy Health that felt more like a defense than a conversation. I answered honestly about handling an accelerated launch date and am trying not to obsess over their phrasing while waiting to hear back.",
    "mood": "anxious",
    "secondaryMood": "reflective",
    "areas": [
      "work"
    ],
    "tags": [
      "job search",
      "workplace"
    ],
    "mentions": [
      {
        "kind": "organization",
        "name": "Canopy Health"
      },
      {
        "kind": "organization",
        "name": "Ledgerline"
      }
    ],
    "opens": [
      {
        "about": [
          "Canopy Health"
        ],
        "due": "2026-02-06",
        "id": "t030",
        "text": "Waiting to hear back from Canopy Health after the second interview"
      }
    ]
  },
  {
    "date": "2026-02-06T22:30",
    "title": "Drinking at Danny's bar",
    "text": "Went to Danny's bar after closing for some serious drinking, just the two of us and whatever he was pouring, lost count somewhere after the third one. Talked about nothing important for two hours which was exactly what I needed, no interviews, no budget spreadsheet, no Greg. Woke up this morning feeling like garbage, skipped my run, ate cereal standing over the sink at eleven. Maya texted asking how the weekend was going and I said fine, which was not really true, just easier.",
    "summary": "I spent the night drinking with Danny and found the distraction I needed, then woke up feeling physically awful and gave Maya a falsely reassuring answer about the weekend.",
    "mood": "tired",
    "secondaryMood": "relieved",
    "areas": [
      "friends",
      "health"
    ],
    "tags": [
      "late night",
      "processing",
      "running",
      "texting"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Danny"
      },
      {
        "kind": "person",
        "name": "Greg"
      },
      {
        "kind": "person",
        "name": "Maya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "friends"
        ],
        "names": [
          "Danny",
          "Greg"
        ],
        "offset": 0,
        "summary": "I drank with Danny after closing and enjoyed two hours of unimportant conversation without thinking about interviews, the budget spreadsheet, or Greg.",
        "tags": [
          "late night",
          "processing"
        ],
        "topic": "Drinking with Danny"
      },
      {
        "areasRaw": [
          "health"
        ],
        "names": [],
        "offset": 276,
        "summary": "I felt physically awful, skipped my run, and ate cereal standing over the sink.",
        "tags": [
          "running"
        ],
        "topic": "Rough morning"
      },
      {
        "areasRaw": [
          "friends"
        ],
        "names": [
          "Maya"
        ],
        "offset": 380,
        "summary": "I told Maya the weekend was fine even though that was not really true.",
        "tags": [
          "texting"
        ],
        "topic": "Texting Maya"
      }
    ]
  },
  {
    "date": "2026-02-08T16:45",
    "title": "Helping with the business plan",
    "text": "Tacos with Danny again, he finally showed me the actual state of the El Primo paperwork and it's a mess, half finished projections in three different notebooks, no real budget or business plan a bank would look at twice. Told him I'll help him finish the business plan properly since I've got nothing but time right now and it's the one thing this week that felt useful instead of just waiting for my phone to ring. He looked relieved in a way he doesn't usually let show. Starting this weekend, actual spreadsheets, actual numbers.",
    "summary": "I saw that El Primo's paperwork is a mess and told Danny I'll help finish the business plan properly. Starting this weekend, I'll work on actual spreadsheets and numbers, which felt useful instead of waiting for my phone to ring.",
    "mood": "frustrated",
    "secondaryMood": "energized",
    "areas": [
      "work",
      "friends"
    ],
    "tags": [
      "tacos",
      "roadmap"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Danny"
      },
      {
        "kind": "project",
        "name": "El Primo"
      }
    ],
    "opens": [
      {
        "about": [
          "Danny",
          "El Primo"
        ],
        "id": "t031",
        "text": "Finish the El Primo business plan with actual spreadsheets and numbers"
      }
    ]
  },
  {
    "date": "2026-02-10T20:00",
    "title": "Canopy Health goes quiet",
    "text": "Nothing from Canopy Health since Friday, said they'd be in touch by end of week and it's now Tuesday of the next one. Emailed the recruiter a polite check in, no response yet. Starting to recognize this particular flavor of silence. Also need to actually decide about COBRA before the grace period runs out, it's expensive but going without coverage feels like a bad bet given how my luck's been running lately. Sleep's been bad again, up at three most nights doing budget math in my head.",
    "summary": "I’m waiting to hear back from Canopy Health after checking in with the recruiter. I also need to decide about COBRA while poor sleep keeps pulling me into budget calculations.",
    "mood": "anxious",
    "secondaryMood": "stressed",
    "areas": [
      "work",
      "health"
    ],
    "tags": [
      "job search",
      "budgeting",
      "sleep"
    ],
    "mentions": [
      {
        "kind": "organization",
        "name": "Canopy Health"
      },
      {
        "kind": "other",
        "name": "COBRA"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Canopy Health"
        ],
        "offset": 0,
        "summary": "I’m waiting for a response from Canopy Health after checking in with the recruiter.",
        "tags": [
          "job search"
        ],
        "topic": "Canopy Health silence"
      },
      {
        "areasRaw": [
          "health",
          "money"
        ],
        "names": [
          "COBRA"
        ],
        "offset": 233,
        "summary": "I need to decide whether COBRA’s expense is worth keeping health coverage.",
        "tags": [
          "budgeting"
        ],
        "topic": "COBRA decision"
      },
      {
        "areasRaw": [
          "health",
          "money"
        ],
        "names": [],
        "offset": 412,
        "summary": "I’m sleeping badly and waking at three to do budget math in my head.",
        "tags": [
          "sleep",
          "budgeting"
        ],
        "topic": "Sleep and budget worry"
      }
    ],
    "opens": [
      {
        "about": [
          "COBRA"
        ],
        "id": "t032",
        "text": "Decide whether to take COBRA before the grace period runs out"
      }
    ],
    "touches": [
      "t030"
    ]
  },
  {
    "date": "2026-02-12T19:30",
    "title": "Canceling on Maya",
    "text": "Dating someone shouldn't feel like this, I canceled on Maya twice this week, once for a made up excuse about applications and once because I just didn't have it in me to be around anyone. She didn't push, said take the space you need, but I could hear something careful in her voice on the phone, like she was choosing the words to not make it worse. I know I'm doing the thing Nina called out, going quiet and disappearing into my own head. Knowing it and stopping it are apparently two very different skills.",
    "summary": "I canceled on Maya twice and withdrew because I did not have it in me to be around anyone. I recognize the pattern Nina called out, but knowing it and stopping it feel like different skills.",
    "mood": "guilty",
    "secondaryMood": "conflicted",
    "areas": [
      "love",
      "mind"
    ],
    "tags": [
      "dating",
      "processing"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "person",
        "name": "Nina"
      }
    ]
  },
  {
    "date": "2026-02-13T18:00",
    "title": "Flowers for tomorrow",
    "text": "Picked up flowers and a card for tomorrow, actually planned something instead of winging it for once. Feels important to show up right after a rough couple weeks of being half there. Reservation at seven, the Italian place she mentioned wanting to try. Trying, for once, at dating like it still matters, because it does.",
    "summary": "I picked up flowers and a card and planned a date for tomorrow at seven at the Italian place she mentioned. I want to show up for dating after a rough couple of weeks of being half there.",
    "mood": "hopeful",
    "secondaryMood": "proud",
    "areas": [
      "love"
    ],
    "tags": [
      "dating",
      "gift"
    ],
    "mentions": []
  },
  {
    "date": "2026-02-14T20:00",
    "title": "Valentine's Day, somewhere else",
    "text": "Tried really hard tonight, dating on purpose instead of on autopilot. Flowers, the reservation, wore the shirt she likes, asked real questions about her day and actually listened to the answers instead of waiting for my turn to talk. Dinner was good, the place lived up to the hype. But somewhere around dessert she reached over and said, gently, where'd you go, and I realized I'd been somewhere else for a few minutes, running the budget spreadsheet in my head instead of being at the table. She wasn't mad, just quiet about it in a way that felt worse than mad would have. Said I know you're going through it, I just miss you being here even when you're here. I don't have a good comeback for that because it's true. Walked her home, kissed her goodnight, told her I love you and meant it completely, and still drove home knowing tonight wasn't what I wanted it to be for her. Going to bring this up with Dr. Adler Thursday. Something's stuck and I don't fully understand what yet.",
    "summary": "I tried to date intentionally and be present, but became absorbed in the budget during dinner. I recognized that my absence hurt her and plan to bring the unresolved issue to Dr. Adler Thursday.",
    "mood": "disappointed",
    "secondaryMood": "reflective",
    "areas": [
      "love",
      "mind"
    ],
    "tags": [
      "dating",
      "processing",
      "therapy",
      "dinner",
      "budgeting"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Dr. Adler"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "love"
        ],
        "names": [],
        "offset": 0,
        "summary": "I made a deliberate effort to be present and attentive on the date, and enjoyed the dinner.",
        "tags": [
          "dating",
          "dinner"
        ],
        "topic": "Intentional date night"
      },
      {
        "areasRaw": [
          "love",
          "mind"
        ],
        "names": [],
        "offset": 283,
        "summary": "I realized I had withdrawn into thoughts about the budget, and she told me she misses me even when I am physically there.",
        "tags": [
          "dating",
          "processing",
          "budgeting"
        ],
        "topic": "Being present together"
      },
      {
        "areasRaw": [
          "mind"
        ],
        "names": [
          "Dr. Adler"
        ],
        "offset": 880,
        "summary": "I plan to discuss what feels stuck and unclear with Dr. Adler Thursday.",
        "tags": [
          "therapy",
          "processing"
        ],
        "topic": "Discussing what feels stuck"
      }
    ],
    "touches": [
      "t029"
    ]
  },
  {
    "date": "2026-02-15T21:00",
    "title": "Sunday, trying to be here",
    "text": "Quiet Sunday, tried to sit with what Maya said last night instead of brushing past it. She's right that I've been half here for weeks, money running under everything like a second conversation nobody else can hear. Still haven't heard from Canopy Health, still haven't sorted the COBRA thing, still waiting on money that isn't coming from anywhere yet. But I noticed today, actually noticed, that Pickles was doing his ridiculous thing where he sits in the sink for no reason, and I laughed, a real laugh, first one in a while. Small sign of life. Going to try to be more where I actually am. Starting now, apparently, at eight at night, writing this instead of doing the money math again.",
    "summary": "I sat with what Maya said about being half here while money concerns, Canopy Health, and COBRA remained unresolved. I noticed Pickles, laughed for the first time in a while, and started trying to be more present.",
    "mood": "reflective",
    "secondaryMood": "anxious",
    "areas": [
      "money",
      "mind"
    ],
    "tags": [
      "processing",
      "budgeting",
      "pet",
      "late night"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "organization",
        "name": "Canopy Health"
      },
      {
        "kind": "organization",
        "name": "COBRA"
      },
      {
        "kind": "other",
        "name": "Pickles"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "mind",
          "money"
        ],
        "names": [
          "Maya",
          "Canopy Health",
          "COBRA"
        ],
        "offset": 0,
        "summary": "I sat with what Maya said about being half here, while money concerns, Canopy Health, and COBRA remained unresolved.",
        "tags": [
          "processing",
          "budgeting"
        ],
        "topic": "Sitting with money worries"
      },
      {
        "areasRaw": [
          "play"
        ],
        "names": [
          "Pickles"
        ],
        "offset": 353,
        "summary": "I noticed Pickles sitting in the sink and laughed for the first time in a while.",
        "tags": [
          "pet"
        ],
        "topic": "Pickles in the sink"
      },
      {
        "areasRaw": [
          "mind"
        ],
        "names": [],
        "offset": 548,
        "summary": "I decided to be more present and wrote this instead of doing the money math again.",
        "tags": [
          "processing",
          "late night"
        ],
        "topic": "Being present tonight"
      }
    ],
    "opens": [
      {
        "about": [
          "Canopy Health"
        ],
        "id": "t033",
        "text": "Wait to hear from Canopy Health"
      }
    ],
    "touches": [
      "t032"
    ]
  }
]
"""#
}
#endif
