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
    "summary": "I sat through a standup where Greg refused to move the December 9th launch date despite Priya's warning about untested load.",
    "mood": "irritated",
    "areas": [
      "work"
    ],
    "tags": [
      "launch"
    ],
    "mentions": [
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Priya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-12-05T18:30",
    "title": "Christmas gifts and Pickles",
    "text": "Maya came over after her shift with Thai food and we ended up making the family gift list for Christmas because I am hopeless at this every single year. Nina is the hard one, she already has everything and returns what she doesn't love. Maya suggested a soup subscription thing since Nina complained about not having time to cook. Sold. Also apparently Pickles knocked one of the plants off the windowsill while we were eating and just watched it happen, no remorse.",
    "summary": "Maya helped me pick a Christmas gift for Nina, and Pickles knocked a plant off the windowsill for no reason.",
    "mood": "content",
    "areas": [
      "family",
      "love"
    ],
    "tags": [
      "gift",
      "plants"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Nina",
        "kind": "person"
      }
    ],
    "opens": [
      {
        "id": "c2-gift-nina",
        "text": "Get Nina a Christmas gift",
        "about": [
          "Nina"
        ],
        "due": "2025-12-24"
      }
    ]
  },
  {
    "date": "2025-12-07T19:45",
    "title": "Tacos and a spreadsheet",
    "text": "Tacos at Taqueria Lupita with Danny, al pastor and the green salsa like always. He's got a spreadsheet now for El Primo, actual line items, a guy from the health department he needs to call about the truck inspection. I told him that's more progress than my whole team made this week. He asked how the launch prep was going and I said ask me in two weeks. Walked home and the radiator in the bedroom started making this banging noise, like someone hitting a pipe with a wrench. Hoping it's nothing.",
    "summary": "I had tacos with Danny, who is getting serious about El Primo, and came home to a banging radiator.",
    "mood": "content",
    "secondaryMood": "uncertain",
    "areas": [
      "friends",
      "home"
    ],
    "tags": [
      "tacos",
      "launch"
    ],
    "mentions": [
      {
        "name": "Danny",
        "kind": "person"
      },
      {
        "name": "Taqueria Lupita",
        "kind": "place"
      },
      {
        "name": "El Primo",
        "kind": "project"
      }
    ]
  },
  {
    "date": "2025-12-08T22:30",
    "title": "Radiator gives up",
    "text": "No heat in the bedroom at all now, the radiator banging stopped because the whole thing just gave up. Texted Mr. Kowalski, no response yet. Slept in a hoodie. This apartment.",
    "summary": "The bedroom radiator died completely and I texted Mr. Kowalski, who hasn't answered yet.",
    "mood": "frustrated",
    "areas": [
      "home"
    ],
    "tags": [
      "radiator"
    ],
    "mentions": [
      {
        "name": "Mr. Kowalski",
        "kind": "person"
      }
    ],
    "opens": [
      {
        "id": "fix-radiator",
        "text": "Get Mr. Kowalski to fix the radiator",
        "about": [
          "Mr. Kowalski"
        ],
        "due": "2025-12-15"
      }
    ]
  },
  {
    "date": "2025-12-09T23:50",
    "title": "Payouts v2 goes live",
    "text": "Payouts v2 went live at 6am. By ten I had four Slack threads going and Priya on a call with her voice doing the thing it does when she's trying not to yell. The reconciliation job double counted a batch of transactions from the retry queue and started paying merchants twice. Not five merchants. Not fifty. The number by two o'clock was somewhere north of three hundred and climbing every time the job ran again, because nobody had killed the cron. Greg wanted a one line update for his boss before we even had the number confirmed. I told him I wasn't going to give him a wrong number to make him feel better in a meeting. He didn't love that. Ben found the actual bug around four, a flag that got flipped in a config push two days ago that nobody flagged for QA because it was supposed to be dark until launch. Priya killed the job. We spent the rest of the night writing a script to identify every duplicate payout so finance could start clawing them back tomorrow. Left the office at eleven. Ordered a burrito I didn't taste. Pickles was asleep on my keyboard when I finally sat down and I just left him there for a while.",
    "summary": "Payouts v2 launched and a reconciliation bug double-paid over three hundred merchants; we spent the night building a script to find every duplicate.",
    "mood": "overwhelmed",
    "secondaryMood": "angry",
    "areas": [
      "work"
    ],
    "tags": [
      "launch",
      "bug"
    ],
    "mentions": [
      {
        "name": "Payouts v2",
        "kind": "project"
      },
      {
        "name": "Priya",
        "kind": "person"
      },
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Ben",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-12-10T22:40",
    "title": "Day two of the mess",
    "text": "Second day of the launch fallout. The clawback script Priya and Ben wrote overnight is not perfect, it flagged nineteen merchants as duplicates who weren't, which means nineteen angry emails from actual merchant accounts saying we took money from them for no reason. Spent the whole morning on the phone with support triaging which flags are real. Greg wants a merchant facing statement by end of day that doesn't use the word bug. I said what word does he want me to use instead and he said impacted. Cool. Great word. Very honest. Priya hasn't left the office in about thirty hours, I made her go home at nine. I'm staying because someone has to watch the retry queue and it might as well be me since it's my project. Ate cold pizza standing at my desk, back at work by seven the next morning. Told Maya I couldn't make it tonight and she just said go handle it, I'm not going anywhere. That helped more than I expected.",
    "summary": "The clawback script flagged innocent merchants by mistake, Greg wanted us to avoid the word bug, and Maya told me to go handle it.",
    "mood": "tired",
    "secondaryMood": "resentful",
    "areas": [
      "work"
    ],
    "tags": [
      "launch"
    ],
    "mentions": [
      {
        "name": "Priya",
        "kind": "person"
      },
      {
        "name": "Ben",
        "kind": "person"
      },
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-12-11T21:15",
    "title": "Retry queue finally quiet",
    "text": "Three days after the launch, the retry queue is finally quiet, no new duplicates since midnight. Finance thinks they can recover most of the double payments by Friday, the rest go through a manual outreach process that is going to take weeks. I slept nine hours last night for the first time since Sunday and woke up feeling like I'd been hit by a bus that then backed up and hit me again. Greg sent a calendar invite for Friday titled Payouts v2 Retrospective, no agenda attached. Priya texted just the word 'fun' with no punctuation. I know exactly what that meeting is going to be.",
    "summary": "The retry queue finally went quiet after three days, and Greg scheduled a retrospective for Friday with no agenda.",
    "mood": "tired",
    "secondaryMood": "anxious",
    "areas": [
      "work"
    ],
    "tags": [
      "launch",
      "retrospective"
    ],
    "mentions": [
      {
        "name": "Payouts v2",
        "kind": "project"
      },
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Priya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-12-12T19:50",
    "title": "Writing the postmortem",
    "text": "Wrote the postmortem last night and didn't soften it. Said plainly that the December 9th date was moved up in October against Priya's explicit warning that the reconciliation service hadn't been load tested, that the flag in the config push should have blocked launch and didn't because nobody assigned QA to it under the compressed timeline, and that three hundred and forty merchants were double paid as a direct result. Sent it to Greg before the meeting so he wouldn't be surprised. He was not happy that it named the date as the cause. In the meeting he kept steering it toward process improvements for next time, which is a nice way of saying let's not talk about who set the date. I said the process improvement is not moving dates that engineering says aren't ready. Nobody said anything for a second. Priya looked at me like she was proud of me and terrified for me at the same time. After the meeting Greg stopped by my desk and said, very evenly, that he appreciated my candor, and then didn't say anything else to me the rest of the day. Not hostile. Just cold. Like a switch got flipped. I don't think I imagined it.",
    "summary": "I wrote an honest postmortem naming the rushed launch date as the cause, and Greg went cold on me after the meeting.",
    "mood": "proud",
    "secondaryMood": "anxious",
    "areas": [
      "work"
    ],
    "tags": [
      "postmortem",
      "launch"
    ],
    "mentions": [
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Priya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-12-13T13:30",
    "title": "Shakshuka and a thank you",
    "text": "Slept until eleven, first time in a week. Maya showed up around one with groceries and started cooking, shakshuka, eggs poaching in the tomato sauce while she told me about a kid on her floor who named his IV pole Steve. Told her about Greg going cold on me. She said that says more about him than about you, which is the kind of thing that sounds like a fridge magnet until someone who actually means it says it to you. I should get Priya something, she carried the entire clawback effort on no sleep. Maybe a real thank you note, not just a Slack message.",
    "summary": "Maya made shakshuka and talked me through Greg going cold, and I decided Priya deserves a real thank you for carrying the clawback effort.",
    "mood": "grateful",
    "secondaryMood": "reflective",
    "areas": [
      "love",
      "work"
    ],
    "tags": [
      "cooking"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Priya",
        "kind": "person"
      }
    ],
    "opens": [
      {
        "id": "c2-thankyou-priya",
        "text": "Write Priya a real thank you note",
        "about": [
          "Priya"
        ]
      }
    ]
  },
  {
    "date": "2025-12-14T19:00",
    "title": "Snow and tacos",
    "text": "Tacos with Danny, told him the whole Payouts v2 saga start to finish. He said in bartending years that's like a Saturday during a Bears loss, everybody's mad and someone's getting blamed for something that isn't really their fault. Comforting in its way. He's got a lead on a used truck for El Primo, needs somebody who knows kitchens to look at it with him. Volunteered Maya since she probably knows more about health code than either of us. Walked home in actual snow for the first time this winter, first snow always makes the city look better than it is for about a day.",
    "summary": "I told Danny the whole Payouts v2 story over tacos, and we walked home through the first snow of the winter.",
    "mood": "content",
    "secondaryMood": "nostalgic",
    "areas": [
      "friends"
    ],
    "tags": [
      "tacos"
    ],
    "mentions": [
      {
        "name": "Danny",
        "kind": "person"
      },
      {
        "name": "Payouts v2",
        "kind": "project"
      },
      {
        "name": "El Primo",
        "kind": "project"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-12-16T20:45",
    "title": "No heat again",
    "text": "Still no radiator. Mr. Kowalski says Thursday, which is what he said last Thursday about something else. Ordered a space heater on one day shipping because I can see my breath in the bedroom and that's not a metaphor. Pickles has claimed the one warm spot on the couch and will not be moved.",
    "summary": "The radiator still isn't fixed so I ordered a space heater for the freezing bedroom.",
    "mood": "frustrated",
    "areas": [
      "home"
    ],
    "tags": [
      "radiator"
    ],
    "mentions": [
      {
        "name": "Mr. Kowalski",
        "kind": "person"
      }
    ],
    "opens": [
      {
        "id": "c2-space-heater",
        "text": "Buy a space heater for the cold bedroom"
      }
    ]
  },
  {
    "date": "2025-12-17T22:15",
    "title": "Trivia and a space heater",
    "text": "Trivia at The Brass Tap with Kev and Omar, Quizteama Aguilera finished second because Omar swore the capital of Australia was Sydney with total confidence. Heater arrived and actually works, bedroom is bearable again. Small victories. Kev and Jess are hosting New Year's this year, already looking forward to it.",
    "summary": "Trivia night with Kev and Omar, and the new space heater actually works, so the bedroom is livable again.",
    "mood": "joyful",
    "secondaryMood": "content",
    "areas": [
      "friends"
    ],
    "tags": [
      "trivia"
    ],
    "mentions": [
      {
        "name": "The Brass Tap",
        "kind": "place"
      },
      {
        "name": "Kev",
        "kind": "person"
      },
      {
        "name": "Omar",
        "kind": "person"
      },
      {
        "name": "Jess",
        "kind": "person"
      }
    ],
    "resolves": [
      "c2-space-heater"
    ]
  },
  {
    "date": "2025-12-19T19:30",
    "title": "What do I call this",
    "text": "It's a strange thing about dating in your thirties. Maya asked, kind of out of nowhere while we were doing dishes, what I'd call this if someone at work asked. I said girlfriend, I guess, and she said guess isn't really an answer. Fair. We didn't finish the conversation because her phone rang, a shift swap thing, but I've been thinking about it since. Six weeks in and I already know I don't want to see anyone else. Not sure why that's hard to just say out loud.",
    "summary": "Maya asked what to call our relationship and I gave a wishy-washy answer that I've been thinking about ever since.",
    "mood": "uncertain",
    "secondaryMood": "hopeful",
    "areas": [
      "love"
    ],
    "tags": [
      "dating"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-12-20T22:50",
    "title": "Official",
    "text": "Dating for six weeks and finally told Maya tonight, actually said it without her having to drag it out of me this time. We were at her place, Pickles-less silence, just us and a bad movie neither of us was watching. I said I don't want to guess anymore either, I want to just say it, you're my girlfriend and I'm your boyfriend and that's the thing now. She laughed at how formal I made it sound and then kissed me and said finally. Six weeks of dinners and night shift texts at two in the morning and now it has a name. Feels stupid how much lighter that made me. We ordered pho even though it was ten at night because neither of us wanted to cook, ate it on her couch, and I kept looking over at her like an idiot. Danny is going to make fun of me for how happy I sound. Worth it.",
    "summary": "I told Maya I wanted to make things official, girlfriend and boyfriend, and it felt like a weight lifted.",
    "mood": "joyful",
    "secondaryMood": "relieved",
    "areas": [
      "love"
    ],
    "tags": [
      "dating"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Danny",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-12-22T18:15",
    "title": "Wrapping up before break",
    "text": "Last real work day before the holiday break. Gave Priya a card and a bottle of the mezcal she mentioned liking once in March, felt small compared to what she did for the team but she seemed genuinely touched. Also finally got Nina's gift sorted, the soup subscription, wrapped and shipped before I could talk myself out of something more complicated and worse. Office was half empty by three, everyone checked out early. Greg said happy holidays to me in the hallway like nothing happened between us. I said the same back. We're going to be doing this dance for a while I think.",
    "summary": "I thanked Priya with a small gift, finished Nina's Christmas gift, and had an awkward hallway exchange with Greg before the break.",
    "mood": "content",
    "secondaryMood": "uncertain",
    "areas": [
      "work"
    ],
    "tags": [
      "gift"
    ],
    "mentions": [
      {
        "name": "Priya",
        "kind": "person"
      },
      {
        "name": "Nina",
        "kind": "person"
      },
      {
        "name": "Greg",
        "kind": "person"
      }
    ],
    "resolves": [
      "c2-thankyou-priya",
      "c2-gift-nina"
    ]
  },
  {
    "date": "2025-12-23T20:40",
    "title": "Packing for Naperville",
    "text": "Packing for Naperville tomorrow. Maya's coming for real this time, meeting everyone properly, not just a name Abuela asks about. Told Mom she's vegetarian-adjacent and Mom said that's fine, more tamales for everyone else, which is not really engaging with the information but that's Mom. Nervous in a way I wasn't expecting. Pickles is staying with the downstairs neighbor for two days and already hates me for the carrier coming out.",
    "summary": "I packed for Christmas Eve in Naperville, nervous about Maya finally meeting the whole family properly.",
    "mood": "anxious",
    "secondaryMood": "excited",
    "areas": [
      "family"
    ],
    "tags": [
      "tamales"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Abuela",
        "kind": "person"
      },
      {
        "name": "Mom",
        "kind": "person"
      },
      {
        "name": "Naperville",
        "kind": "place"
      }
    ]
  },
  {
    "date": "2025-12-24T23:30",
    "title": "Christmas Eve tamales",
    "text": "Christmas Eve in Naperville and it went better than I let myself hope for. Abuela pulled Maya into the kitchen within about four minutes of us walking in the door and had her folding masa into corn husks by the time I found them, laughing about something in Spanish faster than Maya could follow, but she was following the folding fine, better than I ever have honestly. Mom kept finding reasons to walk through the kitchen and each time left looking a little more delighted. Dad didn't say much, he never does, but he made a point of getting Maya a beer without being asked and sat next to her at dinner instead of his usual spot, which from Dad is basically a toast. Nina cornered me by the stairs and said, quietly, she's good for you, don't mess it up, which from Nina is basically a hug. Leo made Maya watch him do a dinosaur roar approximately eleven times and she gave each one a genuine rating. Tommy showed up late from a friend's, ate four tamales standing at the counter, asked Maya if she'd ever seen someone die at work and then immediately apologized, which Maya thought was funnier than offensive. Drove home at midnight with tamales in a container on Maya's lap, radio low, both of us quiet in the good way. She said your family is loud in the nicest way I've ever seen loud be. I think that's the whole thing right there.",
    "summary": "Maya spent Christmas Eve with my whole family in Naperville, learned to make tamales with Abuela, and won everyone over.",
    "mood": "grateful",
    "secondaryMood": "loved",
    "areas": [
      "family",
      "love"
    ],
    "tags": [
      "tamales"
    ],
    "mentions": [
      {
        "name": "Abuela",
        "kind": "person"
      },
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Mom",
        "kind": "person"
      },
      {
        "name": "Dad",
        "kind": "person"
      },
      {
        "name": "Nina",
        "kind": "person"
      },
      {
        "name": "Leo",
        "kind": "person"
      },
      {
        "name": "Tommy",
        "kind": "person"
      },
      {
        "name": "Naperville",
        "kind": "place"
      }
    ]
  },
  {
    "date": "2025-12-25T11:30",
    "title": "Quiet Christmas Day",
    "text": "Christmas Day was mercifully low key, still at Mom and Dad's, everyone moving slow after last night. Maya and Abuela were back at it this morning like old friends, going through Abuela's recipe box, actual index cards in handwriting from decades ago. Ava fell asleep under the tree at one point and nobody moved her for an hour. Drove back to the city in the afternoon, quiet drive, good kind of tired.",
    "summary": "Christmas Day was quiet, with Maya and Abuela going through the old recipe box together before we drove home.",
    "mood": "content",
    "secondaryMood": "nostalgic",
    "areas": [
      "family"
    ],
    "tags": [
      "recipe"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Abuela",
        "kind": "person"
      },
      {
        "name": "Mom",
        "kind": "person"
      },
      {
        "name": "Dad",
        "kind": "person"
      },
      {
        "name": "Ava",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-12-27T15:30",
    "title": "Back to the apartment",
    "text": "Back in the apartment, back to normal chaos. Pickles greeted me by knocking a mug off the counter within ninety seconds of the carrier door opening, so, missed me too buddy. Did three loads of laundry I'd been avoiding since before Naperville. Found Maya's phone charger tangled in my sheets, she must have left it last time she stayed over, need to remember to bring it to her before her old one dies completely. Quiet day, good for once. Watched most of a documentary about competitive cheese rolling that made no sense and I loved it.",
    "summary": "Ordinary day back home doing laundry, and I found Maya's charger left behind in my sheets.",
    "mood": "calm",
    "secondaryMood": "content",
    "areas": [
      "home"
    ],
    "tags": [
      "laundry",
      "pickles"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Naperville",
        "kind": "place"
      }
    ],
    "opens": [
      {
        "id": "c2-charger",
        "text": "Return Maya's phone charger",
        "about": [
          "Maya"
        ]
      }
    ]
  },
  {
    "date": "2025-12-31T23:55",
    "title": "New Year's Eve steps",
    "text": "Dating someone on night shifts means holidays land wherever her schedule allows, and this year that meant New Year's Eve at Kev and Jess's, low key by their standards now that Jess is very pregnant and tired by nine most nights, but she made it to midnight on ginger ale and sheer will. Maya came straight from a shift, still a little wired the way she gets after twelve hours on the floor, and somewhere around eleven thirty, sitting on Kev's back steps in the cold because inside got too loud, she said it. Just said, I love you, easy, like she'd been carrying it around and finally set it down. I didn't say it back. I said something like I really care about you, which even as it left my mouth I could hear how it landed wrong, how it sounded like a hedge. She said it's okay, take your time, and meant it, I think, but I saw something close in her face a little. We watched the ball drop on Kev's phone because his TV cable was out, all four of us packed on the back steps counting down badly, out of sync with the actual countdown by about four seconds. Kissed her at midnight. Didn't say it. Drove home mostly quiet, replaying it, hating myself a little for not just saying the true thing when she handed it to me for free.",
    "summary": "Maya told me she loves me on Kev and Jess's back steps at New Year's, and I couldn't say it back.",
    "mood": "conflicted",
    "secondaryMood": "loved",
    "areas": [
      "love"
    ],
    "tags": [
      "dating"
    ],
    "mentions": [
      {
        "name": "Kev",
        "kind": "person"
      },
      {
        "name": "Jess",
        "kind": "person"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-01-01T10:30",
    "title": "New Year hangover",
    "text": "New Year's Day, head a little foggy, replaying last night on a loop. Called Danny around noon because he's the only one who won't tell me what I want to hear. Told him what happened on the steps. He was quiet for a second and then said, you know you love her, right, like it wasn't even a question, so what's actually stopping you from saying it. I didn't have a good answer. Something about the last time I said it first to someone, back in college, and how it didn't end anywhere good. Danny said that was a different person and a different decade, man. He's right. Doesn't make the words easier to get out. This is what dating at thirty one does to you, apparently.",
    "summary": "I told Danny about not saying I love you back to Maya, and he pushed me on why I froze up.",
    "mood": "anxious",
    "secondaryMood": "reflective",
    "areas": [
      "love"
    ],
    "tags": [
      "dating"
    ],
    "mentions": [
      {
        "name": "Danny",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-01-03T21:30",
    "title": "Saying it back",
    "text": "Said it. Saturday morning, both of us still in bed, sun barely up, Maya half asleep against my shoulder, and I just said it, I love you, no lead up, no big moment, just true and out loud before I could talk myself out of it again. She opened one eye and said finally, you goon, and pulled me back down like we hadn't just had a small earthquake happen. Told her about the college thing after, why I froze on the steps, and she just listened, didn't make it a bigger deal than it was. Dating someone who just waits you out instead of pushing, turns out that's the whole trick. Made pancakes badly together, burned the first two, ate them anyway. Best terrible pancakes of my life.",
    "summary": "I finally told Maya I love her, and she just laughed and pulled me back down instead of making it a big deal.",
    "mood": "loved",
    "secondaryMood": "relieved",
    "areas": [
      "love"
    ],
    "tags": [
      "dating"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-01-05T18:45",
    "title": "Charger drop off",
    "text": "Back to work Monday, everyone dragging. Dropped Maya's charger off at her place on my way, she was heading out for a shift and gave me a two second kiss goodbye that somehow made the whole gray Monday better. Greg still weirdly formal with me since the postmortem, three word answers in standup. Whatever. Not my circus today.",
    "summary": "I returned Maya's charger on my way to a gray Monday where Greg was still cold with me.",
    "mood": "neutral",
    "secondaryMood": "content",
    "areas": [
      "work"
    ],
    "tags": [
      "postmortem"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Greg",
        "kind": "person"
      }
    ],
    "resolves": [
      "c2-charger"
    ]
  },
  {
    "date": "2026-01-06T17:20",
    "title": "Radiator finally fixed",
    "text": "Mr. Kowalski's guy finally came and fixed the radiator, three weeks and two days after it died, new part, no charge since it's obviously on him. Bedroom is warm for the first time since before Christmas. Small thing. Felt disproportionately great.",
    "summary": "The radiator finally got fixed after three weeks, and the bedroom is warm again.",
    "mood": "relieved",
    "secondaryMood": "content",
    "areas": [
      "home"
    ],
    "tags": [
      "radiator"
    ],
    "mentions": [
      {
        "name": "Mr. Kowalski",
        "kind": "person"
      }
    ],
    "resolves": [
      "fix-radiator"
    ]
  },
  {
    "date": "2026-01-07T20:50",
    "title": "The performance conversation",
    "text": "Greg pulled me into a conference room at four with no warning, HR language already loaded, said this was a check in about performance following the launch incident. Incident. Like Payouts v2 was weather. He said leadership had concerns about judgment under pressure and about how the postmortem was received by stakeholders, which is a very careful way of saying he didn't like being named. Said he wanted to see improvement over the next month. I asked what specifically that meant, what improvement looks like, and he got vague, said things like alignment and communication style. I said I'd like that in writing since vague feedback is hard to act on. He said he'd send a summary. He has not sent a summary. Sat in my car in the parking garage for ten minutes after, not driving anywhere, just sitting there doing math on how much of this is real performance concern and how much is a guy who got called out publicly finding a legal way to be petty about it. Didn't tell Maya right away. Needed to sit with it first.",
    "summary": "Greg gave me a vague performance talk about the launch incident and never followed up with the written summary he promised.",
    "mood": "anxious",
    "secondaryMood": "angry",
    "areas": [
      "work"
    ],
    "tags": [
      "performance"
    ],
    "mentions": [
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Payouts v2",
        "kind": "project"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-01-09T21:30",
    "title": "Telling Maya about Greg",
    "text": "Told Maya about the performance conversation over dinner, the whole thing, the vague improvement language, the sitting in the parking garage. She got quiet and then said that sounds like someone building a file, not someone trying to help you get better. I hadn't wanted to say that word out loud, file, like a legal document with my name on it, but once she said it I couldn't unhear it. She asked if I'd talked to anyone else at work about it. Just Priya, briefly, and Priya's read was similar, she said watch your back. Two people I trust both landed in the same bad place independently. That tells me something.",
    "summary": "I told Maya about the performance talk, and both she and Priya independently think Greg is building a file against me.",
    "mood": "anxious",
    "secondaryMood": "afraid",
    "areas": [
      "work",
      "love"
    ],
    "tags": [
      "performance"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Priya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-01-13T22:00",
    "title": "Denise added to the invite",
    "text": "Calendar invite from Greg for tomorrow at three, no agenda, just my name and Denise's from HR added as an attendee. Denise doesn't sit in on performance check ins. I know what this is before it happens. Told nobody. Slept maybe two hours.",
    "summary": "Greg scheduled a meeting for tomorrow with HR's Denise added, and I already know what it means.",
    "mood": "afraid",
    "secondaryMood": "numb",
    "areas": [
      "work"
    ],
    "tags": [
      "performance"
    ],
    "mentions": [
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Denise",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-01-14T15:30",
    "title": "Fired",
    "text": "Fired today. Three o'clock, conference room, Greg reading from a paper like he needed the paper to remember my name, Denise next to him with the folder already prepared, severance letter and everything, which means this was decided before I walked in, maybe before Friday even. Greg said the word restructuring. Then he said performance. He used both, which even in the moment I noticed was inconsistent, pick one. Denise walked me through six weeks of severance, COBRA information, a laptop return checklist like I was a piece of hardware being decommissioned. I asked if this was about the Payouts v2 launch and Greg said this isn't about any one thing, which is what people say when it is definitely about one thing. Packed my desk into a cardboard box someone had ready and waiting, which means they knew, everyone probably knew before I did. Priya found me in the elevator lobby, hugged me without saying anything for a second, then said this is not okay and I am going to stay in touch, actually stay in touch, not the fake kind. Ben looked like he wanted to say something and didn't, which I understood, he's twenty six and scared for his own job probably. Walked out of the building I've gone into almost every weekday for three years carrying a box with a desk plant and a mug that says World's Okayest PM that Kev got me as a joke two Christmases ago. Sat in my car in the same parking garage as last week and didn't do math this time, just sat there. Called Maya. She picked up on the first ring like she'd been holding her phone.",
    "summary": "Greg and Denise from HR fired me today, citing both restructuring and performance, with six weeks of severance.",
    "mood": "numb",
    "secondaryMood": "hurt",
    "areas": [
      "work"
    ],
    "tags": [
      "severance",
      "launch"
    ],
    "mentions": [
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Denise",
        "kind": "person"
      },
      {
        "name": "Payouts v2",
        "kind": "project"
      },
      {
        "name": "Priya",
        "kind": "person"
      },
      {
        "name": "Ben",
        "kind": "person"
      },
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Kev",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-01-14T21:00",
    "title": "Pho on the couch",
    "text": "Maya showed up two hours after I called her with a bag from Little Saigon Pho, the good broth, extra basil, didn't ask me to talk about it until I'd eaten most of the bowl. Then she just sat with me on the couch while I said all of it out loud again, the paper Greg read from, the box, Priya in the elevator lobby. She didn't try to fix it or find the silver lining, just kept saying I'm right here, over and over, which turned out to be exactly the right thing to say. Pickles curled up on my lap and didn't move for two hours either, like he knew. I don't know what I did to deserve either of them tonight.",
    "summary": "Maya brought pho and just sat with me while I talked through getting fired.",
    "mood": "sad",
    "secondaryMood": "loved",
    "areas": [
      "love"
    ],
    "tags": [
      "pho"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Little Saigon Pho",
        "kind": "place"
      },
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Priya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-01-15T11:45",
    "title": "Rebuilding the resume",
    "text": "Woke up and for about four seconds forgot, then remembered. That's going to happen for a while probably. Opened my resume for the first time in three years and it is embarrassing, still lists a job I had in 2019. Need to actually rebuild it properly before I send it anywhere, not just patch the dates. Called the unemployment office, was on hold for forty minutes, got disconnected, will try again tomorrow. One thing at a time.",
    "summary": "I started rebuilding my badly outdated resume and got disconnected after forty minutes on hold with the unemployment office.",
    "mood": "numb",
    "secondaryMood": "uncertain",
    "areas": [
      "work",
      "money"
    ],
    "tags": [
      "resume",
      "unemployment"
    ],
    "mentions": [],
    "opens": [
      {
        "id": "c2-resume-update",
        "text": "Rebuild the resume before applying anywhere",
        "due": "2026-01-24"
      }
    ]
  },
  {
    "date": "2026-01-16T18:30",
    "title": "Telling Dad",
    "text": "Drove out to Naperville to tell Dad in person before he heard it secondhand from Mom who heard it from Nina who I'd already told on the phone, small family, bad telephone game. Told him at the kitchen table, plain, got fired, severance, going to be fine financially for a while. Dad didn't say much, which from him usually means he's working something out internally before he speaks. Finally he said, you'll find something, you're good at what you do, this guy Greg sounds like a jerk. Coming from Dad, jerk is close to a curse word. Then he got quiet again and I could tell he was thinking about his own layoff years ago, the electrician job that folded when I was a kid, how long it took him to find steady work again. He didn't say any of that out loud. Didn't need to. Hugged him on the way out, which we don't really do, and he let it go a beat longer than usual.",
    "summary": "I told Dad in person that I got fired, and he reacted quietly, thinking about his own old layoff without saying so.",
    "mood": "guilty",
    "secondaryMood": "loved",
    "areas": [
      "family"
    ],
    "tags": [
      "severance"
    ],
    "mentions": [
      {
        "name": "Dad",
        "kind": "person"
      },
      {
        "name": "Mom",
        "kind": "person"
      },
      {
        "name": "Nina",
        "kind": "person"
      },
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Naperville",
        "kind": "place"
      }
    ]
  },
  {
    "date": "2026-01-18T16:00",
    "title": "Nina and Maya both say it",
    "text": "Nina called, blunt as always, said losing the job isn't the thing I should be worried about, it's how I get quiet and disappear into my own head when things go bad, she's watched me do it since we were kids. Said flatly, you should try therapy, an actual professional, not just Danny and a six pack. Maya said almost the same thing an hour later like they'd coordinated it, which they hadn't, she said she's noticed me going somewhere else in my head lately even before the firing. I got a little defensive, said I'm handling it fine. Neither of them looked convinced. Honestly neither am I.",
    "summary": "Nina and Maya both independently told me I should see a therapist, and I got defensive even though they were probably right.",
    "mood": "irritated",
    "secondaryMood": "insecure",
    "areas": [
      "mind",
      "family"
    ],
    "tags": [
      "therapy"
    ],
    "mentions": [
      {
        "name": "Nina",
        "kind": "person"
      },
      {
        "name": "Danny",
        "kind": "person"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-01-24T11:00",
    "title": "Resume done, Café Olmo",
    "text": "Finally rebuilt the resume top to bottom, took an entire Saturday, but it's done and it actually reads like something someone would call back for. Started working out of Café Olmo this week since sitting alone in the apartment all day was making me stir crazy, the guy behind the counter already knows my order, a small thing that helps more than it should. Applied to six places today. Budget spreadsheet says the severance plus savings gets me to about June if I'm careful. If. Going to be careful.",
    "summary": "I finished rebuilding my resume, started working out of Café Olmo, and applied to six jobs.",
    "mood": "hopeful",
    "secondaryMood": "anxious",
    "areas": [
      "work",
      "money"
    ],
    "tags": [
      "resume",
      "budget"
    ],
    "mentions": [
      {
        "name": "Café Olmo",
        "kind": "place"
      }
    ],
    "resolves": [
      "c2-resume-update"
    ]
  },
  {
    "date": "2026-01-26T13:30",
    "title": "First Canopy Health round",
    "text": "First real interview since getting fired, a product manager role at Canopy Health, video call from Café Olmo with headphones on so the espresso machine wouldn't ruin it. Went fine I think, maybe better than fine, the hiring manager seemed to actually light up when I talked about the reconciliation disaster and how I handled the postmortem, which is a strange thing to be selling as a strength but here we are. Second round scheduled for next week if this goes well. First time in two weeks I've felt like a person with a future instead of a guy with a box of desk stuff in his closet.",
    "summary": "I had a first interview with Canopy Health that went well, my first real hopeful feeling since getting fired.",
    "mood": "hopeful",
    "secondaryMood": "relieved",
    "areas": [
      "work"
    ],
    "tags": [
      "interview",
      "postmortem"
    ],
    "mentions": [
      {
        "name": "Canopy Health",
        "kind": "organization"
      },
      {
        "name": "Café Olmo",
        "kind": "place"
      }
    ]
  },
  {
    "date": "2026-01-29T19:15",
    "title": "First session with Dr. Adler",
    "text": "First session with Dr. Adler today, six o'clock, a small office above a dry cleaner that did not look like what I pictured. Went in expecting to talk about the firing and mostly ended up talking about my dad instead, which surprised me, I don't know how we got there. Dr. Adler didn't do the thing I was braced for, the nodding and mm-hmm and here's how that makes you feel. Mostly just asked plain questions. What do you actually want right now, not what do you think you should want. I didn't have a clean answer. Told him I've been skeptical about this whole thing, therapy, that it feels like paying someone to listen to me complain. He said that's a fair thing to be skeptical about and we'll find out together if it's true. Fifty minutes went by fast, faster than I expected. Walked out into the cold feeling strange, not lighter exactly, more like something got stirred up that used to sit still. A hundred and eighty dollars for that, partly out of pocket now with no work insurance. Going back Thursday anyway.",
    "summary": "I had my first therapy session with Dr. Adler, expecting to talk about the firing but ending up talking about Dad instead.",
    "mood": "reflective",
    "secondaryMood": "uncertain",
    "areas": [
      "mind"
    ],
    "tags": [
      "therapy"
    ],
    "mentions": [
      {
        "name": "Dr. Adler",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-02-01T17:30",
    "title": "Tacos and budget math",
    "text": "Tacos with Danny, told him the actual numbers, severance running down faster than I want to admit because COBRA alone is eating a chunk of it every month. He didn't try to fix it, just said El Primo's going to need someone who can read a spreadsheet once the loan comes through, keep that in your back pocket. Half joke, half not. Walked home past the closed farmers market lot thinking about money more than I have in years, actually doing math in my head at the taco counter like some kind of stress reflex now.",
    "summary": "I told Danny how fast my severance is going, and money math has become a constant background stress.",
    "mood": "anxious",
    "secondaryMood": "tired",
    "areas": [
      "money",
      "friends"
    ],
    "tags": [
      "tacos"
    ],
    "mentions": [
      {
        "name": "Danny",
        "kind": "person"
      },
      {
        "name": "El Primo",
        "kind": "project"
      }
    ]
  },
  {
    "date": "2026-02-04T20:30",
    "title": "Second Canopy Health round",
    "text": "Second interview round with Canopy Health, three people this time on the call instead of one, felt more like a defense than a conversation. One of them asked how I'd handle a launch date being moved up against engineering's objection, which felt like a very specific question for them to ask a guy who just got fired for exactly that. Answered honestly, said I'd document the risk in writing and escalate above the person moving it if needed, which is exactly what I didn't do enough of at Ledgerline. They said they'd be in touch by end of week. Trying not to obsess over the phrasing of that.",
    "summary": "Canopy Health's second round asked pointed questions about launch dates, and I answered honestly about what I should have done differently at Ledgerline.",
    "mood": "anxious",
    "secondaryMood": "hopeful",
    "areas": [
      "work"
    ],
    "tags": [
      "interview",
      "launch"
    ],
    "mentions": [
      {
        "name": "Canopy Health",
        "kind": "organization"
      },
      {
        "name": "Ledgerline",
        "kind": "organization"
      }
    ]
  },
  {
    "date": "2026-02-06T22:30",
    "title": "Drinking at Danny's bar",
    "text": "Went to Danny's bar after closing for some serious drinking, just the two of us and whatever he was pouring, lost count somewhere after the third one. Talked about nothing important for two hours which was exactly what I needed, no interviews, no budget spreadsheet, no Greg. Woke up this morning feeling like garbage, skipped my run, ate cereal standing over the sink at eleven. Maya texted asking how the weekend was going and I said fine, which was not really true, just easier.",
    "summary": "I drank too much at Danny's bar to avoid thinking about everything, then lied to Maya about how the weekend went.",
    "mood": "numb",
    "secondaryMood": "guilty",
    "areas": [
      "friends",
      "health"
    ],
    "tags": [
      "drinking"
    ],
    "mentions": [
      {
        "name": "Danny",
        "kind": "person"
      },
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-02-08T16:45",
    "title": "Helping with the business plan",
    "text": "Tacos with Danny again, he finally showed me the actual state of the El Primo paperwork and it's a mess, half finished projections in three different notebooks, no real budget or business plan a bank would look at twice. Told him I'll help him finish the business plan properly since I've got nothing but time right now and it's the one thing this week that felt useful instead of just waiting for my phone to ring. He looked relieved in a way he doesn't usually let show. Starting this weekend, actual spreadsheets, actual numbers.",
    "summary": "I offered to help Danny finish the El Primo business plan properly, which felt like the first useful thing I'd done in weeks.",
    "mood": "content",
    "secondaryMood": "hopeful",
    "areas": [
      "friends",
      "money"
    ],
    "tags": [
      "tacos",
      "budget"
    ],
    "mentions": [
      {
        "name": "Danny",
        "kind": "person"
      },
      {
        "name": "El Primo",
        "kind": "project"
      }
    ],
    "opens": [
      {
        "id": "danny-business-plan",
        "text": "Finish the business plan for El Primo",
        "about": [
          "Danny",
          "El Primo"
        ],
        "due": "2026-03-01"
      }
    ]
  },
  {
    "date": "2026-02-10T20:00",
    "title": "Canopy Health goes quiet",
    "text": "Nothing from Canopy Health since Friday, said they'd be in touch by end of week and it's now Tuesday of the next one. Emailed the recruiter a polite check in, no response yet. Starting to recognize this particular flavor of silence. Also need to actually decide about COBRA before the grace period runs out, it's expensive but going without coverage feels like a bad bet given how my luck's been running lately. Sleep's been bad again, up at three most nights doing budget math in my head.",
    "summary": "Canopy Health went silent after saying they'd follow up, and I still need to decide about COBRA before the deadline.",
    "mood": "anxious",
    "secondaryMood": "tired",
    "areas": [
      "money",
      "health"
    ],
    "tags": [
      "budget",
      "sleep"
    ],
    "mentions": [
      {
        "name": "Canopy Health",
        "kind": "organization"
      }
    ],
    "opens": [
      {
        "id": "c2-cobra-decision",
        "text": "Decide about COBRA before the grace period ends"
      }
    ]
  },
  {
    "date": "2026-02-12T19:30",
    "title": "Canceling on Maya",
    "text": "Dating someone shouldn't feel like this, I canceled on Maya twice this week, once for a made up excuse about applications and once because I just didn't have it in me to be around anyone. She didn't push, said take the space you need, but I could hear something careful in her voice on the phone, like she was choosing the words to not make it worse. I know I'm doing the thing Nina called out, going quiet and disappearing into my own head. Knowing it and stopping it are apparently two very different skills.",
    "summary": "I canceled on Maya twice this week and can hear myself doing the same withdrawing thing Nina warned me about.",
    "mood": "guilty",
    "secondaryMood": "sad",
    "areas": [
      "love",
      "mind"
    ],
    "tags": [
      "dating"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Nina",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-02-13T18:00",
    "title": "Flowers for tomorrow",
    "text": "Picked up flowers and a card for tomorrow, actually planned something instead of winging it for once. Feels important to show up right after a rough couple weeks of being half there. Reservation at seven, the Italian place she mentioned wanting to try. Trying, for once, at dating like it still matters, because it does.",
    "summary": "I planned ahead for Valentine's Day, flowers and a dinner reservation, after weeks of being distant.",
    "mood": "hopeful",
    "secondaryMood": "anxious",
    "areas": [
      "love"
    ],
    "tags": [
      "dating"
    ],
    "mentions": []
  },
  {
    "date": "2026-02-14T20:00",
    "title": "Valentine's Day, somewhere else",
    "text": "Tried really hard tonight, dating on purpose instead of on autopilot. Flowers, the reservation, wore the shirt she likes, asked real questions about her day and actually listened to the answers instead of waiting for my turn to talk. Dinner was good, the place lived up to the hype. But somewhere around dessert she reached over and said, gently, where'd you go, and I realized I'd been somewhere else for a few minutes, running the budget spreadsheet in my head instead of being at the table. She wasn't mad, just quiet about it in a way that felt worse than mad would have. Said I know you're going through it, I just miss you being here even when you're here. I don't have a good comeback for that because it's true. Walked her home, kissed her goodnight, told her I love you and meant it completely, and still drove home knowing tonight wasn't what I wanted it to be for her. Going to bring this up with Dr. Adler Thursday. Something's stuck and I don't fully understand what yet.",
    "summary": "I tried hard for Valentine's Day but Maya caught me drifting off into worry about money, and it wasn't the night either of us wanted.",
    "mood": "sad",
    "secondaryMood": "loved",
    "areas": [
      "love",
      "mind"
    ],
    "tags": [
      "dating",
      "budget"
    ],
    "mentions": [
      {
        "name": "Dr. Adler",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2026-02-15T21:00",
    "title": "Sunday, trying to be here",
    "text": "Quiet Sunday, tried to sit with what Maya said last night instead of brushing past it. She's right that I've been half here for weeks, money running under everything like a second conversation nobody else can hear. Still haven't heard from Canopy Health, still haven't sorted the COBRA thing, still waiting on money that isn't coming from anywhere yet. But I noticed today, actually noticed, that Pickles was doing his ridiculous thing where he sits in the sink for no reason, and I laughed, a real laugh, first one in a while. Small sign of life. Going to try to be more where I actually am. Starting now, apparently, at eight at night, writing this instead of doing the money math again.",
    "summary": "I sat with what Maya said about me being distracted, still haven't resolved COBRA or heard back from Canopy Health, but found a small real laugh today.",
    "mood": "reflective",
    "secondaryMood": "hopeful",
    "areas": [
      "mind",
      "money"
    ],
    "tags": [
      "pickles",
      "cobra"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Canopy Health",
        "kind": "organization"
      }
    ],
    "touches": [
      "c2-cobra-decision"
    ]
  }
]
"""#
}
#endif
