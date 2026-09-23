#if DEBUG
// Generated from the story bible in docs/demo-story.md. Edit the JSON in place; DemoStoryTests
// checks every name, tag, and loose end against the text.
extension DemoStory {
    static let chapter1 = #"""
[
  {
    "date": "2025-09-23T19:10",
    "title": "Greg's first day",
    "text": "New VP of Product started today. Greg. Walked into the all-hands with a deck already built, our whole roadmap moved around like furniture in someone else's apartment. Priya caught my eye twice. Ledgerline hired him away from some ad-tech place and he already says 'velocity' like it means something. I still like this job. Ask me again in a month.",
    "summary": "I met Greg, the new VP of Product, and watched him immediately rearrange our roadmap. I still like my job, but I want to reassess how I feel in a month.",
    "mood": "frustrated",
    "secondaryMood": "uncertain",
    "areas": [
      "work"
    ],
    "tags": [
      "leadership change",
      "roadmap",
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
      },
      {
        "kind": "organization",
        "name": "Ledgerline"
      }
    ]
  },
  {
    "date": "2025-09-24T20:30",
    "title": "Quizteama loses again",
    "text": "Trivia at The Brass Tap with Kev and Omar. Team name is still Quizteama Aguilera, we are still bad at sports questions and somehow worse at capitals. Came in fourth out of nine, which for us is basically winning. Kev bought the pitcher to celebrate not being last. Omar left early, has to go running in the morning now that his knee finally stopped bugging him. Good night anyway.",
    "summary": "I had trivia at The Brass Tap with Kev and Omar, finishing fourth out of nine and celebrating with a pitcher. Omar left early for a morning run now that his knee has stopped bothering him, but it was a good night anyway.",
    "mood": "joyful",
    "secondaryMood": "connected",
    "areas": [
      "friends",
      "play"
    ],
    "tags": [
      "trivia night",
      "quizteama aguilera",
      "running",
      "knee recovery"
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
        "kind": "other",
        "name": "Quizteama Aguilera"
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
        "summary": "I played trivia with Kev and Omar, came in fourth out of nine, and celebrated with a pitcher despite our poor sports and capitals knowledge.",
        "tags": [
          "trivia night"
        ],
        "topic": "Trivia night"
      },
      {
        "areasRaw": [
          "friends",
          "health"
        ],
        "names": [
          "Omar"
        ],
        "offset": 265,
        "summary": "Omar left early to run in the morning now that his knee has stopped bothering him, and I still had a good night.",
        "tags": [
          "running",
          "knee recovery"
        ],
        "topic": "Omar's morning run"
      }
    ]
  },
  {
    "date": "2025-09-26T18:00",
    "title": "Pickles versus the plant",
    "text": "Came home to potting soil all over the kitchen floor and Pickles sitting in the middle of it looking extremely pleased with himself. The plant did not survive. Neither did my patience for a minute. Cleaned it up, gave him tuna out of guilt even though it was clearly not deserved. Quiet Friday otherwise. Ordered pho, watched half a show, fell asleep on the couch.",
    "summary": "I came home to a kitchen-floor mess caused by Pickles and a plant that did not survive. I cleaned up, ordered pho, watched half a show, and fell asleep on the couch.",
    "mood": "irritated",
    "secondaryMood": "tired",
    "areas": [
      "home",
      "play"
    ],
    "tags": [
      "pet mishap",
      "quiet evening"
    ],
    "mentions": [
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
          "Pickles"
        ],
        "offset": 0,
        "summary": "I found potting soil across the kitchen floor, cleaned it up, and gave Pickles tuna out of guilt after the plant was destroyed.",
        "tags": [
          "pet mishap"
        ],
        "topic": "Potting soil mess"
      },
      {
        "areasRaw": [
          "play"
        ],
        "names": [],
        "offset": 281,
        "summary": "I spent a quiet Friday ordering pho, watching half a show, and falling asleep on the couch.",
        "tags": [
          "quiet evening"
        ],
        "topic": "Quiet Friday evening"
      }
    ]
  },
  {
    "date": "2025-09-28T13:15",
    "title": "Sunday tacos with Danny",
    "text": "Sunday tacos at Taqueria Lupita, the usual, al pastor and the green salsa that makes my nose run. Danny had his notebook out again, sketching menu ideas for El Primo's truck on a napkin. He wants three items max to start: al pastor, a vegetarian option, and horchata that's actually good instead of the syrupy stuff most trucks serve. Told him I'd help him put real numbers behind the menu instead of just vibes. He said that's why he loves me. Also said if I ever quit my job I'm required to work the window for free.",
    "summary": "I shared Sunday tacos with Danny and agreed to help put real numbers behind the three-item menu for El Primo's truck. We exchanged affectionate jokes about his saying he loves me and making me work the window if I quit my job.",
    "mood": "loved",
    "secondaryMood": "connected",
    "areas": [
      "love",
      "work"
    ],
    "tags": [
      "tacos",
      "food truck",
      "menu planning",
      "sunday outing"
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
        "name": "El Primo's truck"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "love",
          "play"
        ],
        "names": [
          "Taqueria Lupita",
          "Danny"
        ],
        "offset": 0,
        "summary": "I shared my usual tacos with Danny and enjoyed the green salsa, even though it made my nose run.",
        "tags": [
          "tacos",
          "sunday outing"
        ],
        "topic": "Sunday taco outing"
      },
      {
        "areasRaw": [
          "work",
          "love"
        ],
        "names": [
          "Danny",
          "El Primo's truck"
        ],
        "offset": 98,
        "summary": "I agreed to help Danny put real numbers behind the three-item menu for El Primo's truck, and we exchanged affectionate jokes about working there together.",
        "tags": [
          "food truck",
          "menu planning"
        ],
        "topic": "Food truck planning"
      }
    ],
    "opens": [
      {
        "about": [
          "Danny",
          "El Primo's truck"
        ],
        "id": "t001",
        "text": "Help put real numbers behind the menu"
      }
    ]
  },
  {
    "date": "2025-09-30T21:45",
    "title": "Payouts v2 moves up",
    "text": "Greg pulled Payouts v2 up to December in the roadmap review today. It was supposed to launch in March. Nobody asked engineering if that's realistic, they just asked me to make the slide work. Priya pulled me aside after and asked if I'd pushed back. I said I tried. I did not try very hard. Grabbing lunch with her this week to actually talk about it instead of doing it in a hallway.",
    "summary": "Payouts v2 was pushed from a March launch to December without an engineering reality check, and I was asked to make the roadmap slide work. I admitted to Priya that I had not pushed back very hard and plan to discuss it with her over lunch this week.",
    "mood": "frustrated",
    "secondaryMood": "guilty",
    "areas": [
      "work"
    ],
    "tags": [
      "roadmap",
      "workplace"
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
        "name": "Priya"
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
        "summary": "Greg moved Payouts v2's launch target from March to December during the roadmap review without checking whether engineering could meet it, leaving me to make the slide work.",
        "tags": [
          "roadmap",
          "workplace"
        ],
        "topic": "Payouts v2 roadmap"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Priya"
        ],
        "offset": 192,
        "summary": "Priya asked whether I had pushed back, and I acknowledged that I had tried but not very hard; I plan to discuss it with her over lunch this week.",
        "tags": [
          "workplace"
        ],
        "topic": "Talking with Priya"
      }
    ],
    "opens": [
      {
        "about": [
          "Priya"
        ],
        "id": "t002",
        "text": "Have lunch with Priya to discuss the roadmap pushback"
      }
    ]
  },
  {
    "date": "2025-10-02T08:20",
    "title": "Flat tire, borrowed drill",
    "text": "Bike had a flat again this morning, walked to the train instead and was fifteen minutes late on the commute. Need to actually fix the tire instead of pumping it every three days and pretending that's a solution. Also still have Dad's drill from putting up shelves in August, should get that back to him before he asks in that voice that isn't asking. Coffee at Café Olmo on the way in, same order, same barista who still doesn't know my name.",
    "summary": "I was late to my commute after another bike flat and need to fix the tire properly. I also need to return Dad's drill and noticed the familiar routine at Café Olmo.",
    "mood": "frustrated",
    "secondaryMood": "irritated",
    "areas": [
      "work",
      "home"
    ],
    "tags": [
      "flat tire",
      "commute",
      "borrowed tools",
      "coffee",
      "shelves"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Dad"
      },
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
        "summary": "I dealt with another flat bike tire, walked to the train, and arrived fifteen minutes late to my commute.",
        "tags": [
          "flat tire",
          "commute"
        ],
        "topic": "Bike and commute"
      },
      {
        "areasRaw": [
          "home"
        ],
        "names": [
          "Dad"
        ],
        "offset": 212,
        "summary": "I still have Dad's drill from putting up shelves in August and need to return it.",
        "tags": [
          "borrowed tools",
          "shelves"
        ],
        "topic": "Returning Dad's drill"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Café Olmo"
        ],
        "offset": 351,
        "summary": "I stopped for my usual coffee at Café Olmo, where the barista still does not know my name.",
        "tags": [
          "coffee"
        ],
        "topic": "Coffee stop"
      }
    ],
    "opens": [
      {
        "id": "t003",
        "text": "Actually fix the tire"
      },
      {
        "about": [
          "Dad"
        ],
        "id": "t004",
        "text": "Return Dad's drill"
      }
    ]
  },
  {
    "date": "2025-10-05T12:40",
    "title": "Tommy stress call",
    "text": "Tommy called during lunch, panicking about a stats final with finals week bearing down and grad school apps he hasn't started. Told him senior year is supposed to feel like this, that I panicked plenty at UIUC too and it worked out. He wasn't fully buying it. Promised to call Sunday night instead of during finals week chaos next time.",
    "summary": "I talked Tommy through his panic about his stats final, finals week, and unstarted grad school applications, sharing that I panicked during senior year at UIUC too. I promised to call him Sunday night next time instead of during finals week chaos.",
    "mood": "compassionate",
    "secondaryMood": "connected",
    "areas": [
      "friends"
    ],
    "tags": [
      "college stress"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Tommy"
      }
    ],
    "opens": [
      {
        "about": [
          "Tommy"
        ],
        "id": "t005",
        "text": "Call Tommy Sunday night instead of during finals week chaos"
      }
    ]
  },
  {
    "date": "2025-10-06T19:00",
    "title": "New tire, evening run",
    "text": "Finally fixed the bike tire on my lunch break, guy at the shop did it in ten minutes and made me feel dumb for not doing it myself two weeks ago. Went running along the Lakefront Trail after work, first cold one of the season, could see my breath by the time I got back. Legs felt good. Ordered too much Thai food and ate all of it standing at the counter like an animal.",
    "summary": "I fixed my bike tire, went for a cold-weather run along the Lakefront Trail, and ate too much Thai food standing at the counter.",
    "mood": "relieved",
    "secondaryMood": "content",
    "areas": [
      "health",
      "play"
    ],
    "tags": [
      "flat tire",
      "running",
      "thai food"
    ],
    "mentions": [
      {
        "kind": "place",
        "name": "Lakefront Trail"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "play"
        ],
        "names": [],
        "offset": 0,
        "summary": "I finally fixed my bike tire during my lunch break, though the shop worker made me feel dumb for not doing it myself.",
        "tags": [
          "flat tire"
        ],
        "topic": "Bike tire repair"
      },
      {
        "areasRaw": [
          "health"
        ],
        "names": [
          "Lakefront Trail"
        ],
        "offset": 146,
        "summary": "I went running along the Lakefront Trail after work in the first cold weather of the season, and my legs felt good.",
        "tags": [
          "running"
        ],
        "topic": "Cold-weather run"
      },
      {
        "areasRaw": [
          "health"
        ],
        "names": [],
        "offset": 287,
        "summary": "I ordered too much Thai food and ate all of it standing at the counter.",
        "tags": [
          "thai food"
        ],
        "topic": "Thai food dinner"
      }
    ],
    "resolves": [
      "t004"
    ]
  },
  {
    "date": "2025-10-08T13:00",
    "title": "Lunch with Priya",
    "text": "Got lunch with Priya finally, away from the office so we could actually talk about the roadmap. She thinks December is not happening without cutting scope hard, and that Greg either doesn't know that or doesn't care. Told her I'd raise it again but honestly I don't know how hard I can push this early with a new VP. Also swung by Naperville after work and dropped Dad's drill back off, he acted like he'd forgotten he ever lent it to me, which is very him.",
    "summary": "I had lunch with Priya to discuss the roadmap and the risk that December will require major scope cuts, but I am unsure how hard to push the issue with the new VP. I also returned Dad's drill after work.",
    "mood": "uncertain",
    "secondaryMood": "frustrated",
    "areas": [
      "work",
      "family"
    ],
    "tags": [
      "roadmap",
      "workplace",
      "borrowed tools"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Priya"
      },
      {
        "kind": "person",
        "name": "Greg"
      },
      {
        "kind": "place",
        "name": "Naperville"
      },
      {
        "kind": "person",
        "name": "Dad"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Priya",
          "Greg"
        ],
        "offset": 0,
        "summary": "I had lunch with Priya to discuss the roadmap, and I am unsure how forcefully to push the scope concern with the new VP.",
        "tags": [
          "roadmap",
          "workplace"
        ],
        "topic": "Roadmap scope discussion"
      },
      {
        "areasRaw": [
          "family"
        ],
        "names": [
          "Naperville",
          "Dad"
        ],
        "offset": 317,
        "summary": "I returned Dad's drill in Naperville after work.",
        "tags": [
          "borrowed tools"
        ],
        "topic": "Returning Dad's drill"
      }
    ],
    "resolves": [
      "t002",
      "t003"
    ]
  },
  {
    "date": "2025-10-10T22:15",
    "title": "Party tomorrow",
    "text": "Rosa and Luis's engagement party is tomorrow at The Brass Tap. Danny's been texting the group chat about what to wear like it's a wedding and not forty people and a cake. Bought a card. Should probably iron a shirt instead of steaming it in the bathroom with the shower running like I always do.",
    "summary": "I’m going to Rosa and Luis’s engagement party tomorrow at The Brass Tap. I bought a card and should iron a shirt instead of steaming it in the bathroom.",
    "mood": "irritated",
    "areas": [
      "friends"
    ],
    "tags": [
      "engagement party",
      "card",
      "dress code"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Rosa"
      },
      {
        "kind": "person",
        "name": "Luis"
      },
      {
        "kind": "event",
        "name": "Rosa and Luis's engagement party"
      },
      {
        "kind": "place",
        "name": "The Brass Tap"
      },
      {
        "kind": "person",
        "name": "Danny"
      }
    ],
    "opens": [
      {
        "due": "2025-10-11",
        "id": "t006",
        "text": "Iron a shirt"
      }
    ]
  },
  {
    "date": "2025-10-11T23:50",
    "title": "Rosa's engagement party",
    "text": "Rosa and Luis's engagement party at The Brass Tap, the whole family there plus half of Luis's hospital. Tía Carmen cried before anyone even gave a toast. Danny gave a toast that started as a joke about Luis's scrubs and ended with him actually choking up, which none of us expected from him. Tío Ray kept refilling everyone's glasses whether they wanted it or not.\n\nLuis introduced me to a friend of his from Lakeshore Children's, a nurse named Maya. We ended up talking for something like two hours, mostly near the plant Rosa had put on the bar as decoration that nobody was supposed to touch. She has three plants in her apartment that she's convinced are all dying and one that refuses to. We talked about bad roommates, she had one who used to eat other people's labeled leftovers and lie about it with a straight face. I talked too much about Payouts v2, which she somehow made sound interesting by asking good questions instead of nodding politely.\n\nGot her number before Danny dragged me over to take a group photo. Keep thinking about the way she laughed at the leftover story, this full unguarded thing, nothing careful about it. Might be reading into one good conversation. Don't care, it was a good conversation.",
    "summary": "I celebrated Rosa and Luis's engagement party with family and Luis's hospital colleagues. I also had a long, unexpectedly good conversation with Maya, got her number, and keep thinking about her laugh.",
    "mood": "joyful",
    "secondaryMood": "connected",
    "areas": [
      "friends",
      "love"
    ],
    "tags": [
      "engagement party",
      "payouts v2"
    ],
    "mentions": [
      {
        "kind": "event",
        "name": "Rosa and Luis's engagement party"
      },
      {
        "kind": "place",
        "name": "The Brass Tap"
      },
      {
        "kind": "person",
        "name": "Luis"
      },
      {
        "kind": "person",
        "name": "Tía Carmen"
      },
      {
        "kind": "person",
        "name": "Danny"
      },
      {
        "kind": "person",
        "name": "Tío Ray"
      },
      {
        "kind": "organization",
        "name": "Lakeshore Children's"
      },
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "project",
        "name": "Payouts v2"
      },
      {
        "kind": "person",
        "name": "Rosa"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "love",
          "friends"
        ],
        "names": [
          "Rosa and Luis's engagement party",
          "The Brass Tap",
          "Luis",
          "Tía Carmen",
          "Danny",
          "Tío Ray",
          "Rosa"
        ],
        "offset": 0,
        "summary": "I celebrated Rosa and Luis's engagement party with the whole family and Luis's hospital colleagues, including emotional toasts and persistent refills from Tío Ray.",
        "tags": [
          "engagement party"
        ],
        "topic": "engagement party"
      },
      {
        "areasRaw": [
          "friends",
          "work"
        ],
        "names": [
          "Luis",
          "Lakeshore Children's",
          "Maya",
          "Payouts v2",
          "Danny"
        ],
        "offset": 366,
        "summary": "I spent about two hours talking with Maya about plants, roommates, and Payouts v2, got her number, and kept thinking about her unguarded laugh.",
        "tags": [
          "payouts v2"
        ],
        "topic": "meeting Maya"
      }
    ]
  },
  {
    "date": "2025-10-13T21:00",
    "title": "Texting Maya",
    "text": "Maya and I have been texting since Saturday, nothing heavy, just back and forth about her impossible dying plants and a show she's convinced I need to watch. She works nights most of the week which already sounds like it's going to be a scheduling puzzle, but she made a joke about it instead of apologizing for it, which I liked. Asked her to dinner. She said yes before I finished the sentence, or at least before I finished typing it.",
    "summary": "I’ve been texting Maya since Saturday, and she said yes to dinner.",
    "mood": "excited",
    "secondaryMood": "hopeful",
    "areas": [
      "love"
    ],
    "tags": [
      "dating",
      "texting",
      "dinner"
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
        "id": "t007",
        "text": "Plan dinner with Maya"
      }
    ]
  },
  {
    "date": "2025-10-14T19:30",
    "title": "Burnt dinner",
    "text": "Tried to make chicken thighs the way Maya described cooking hers, got distracted answering a work email and burned them black on one side. Salvaged what I could, ate it anyway out of stubbornness. Spent the rest of the night texting her about it, and she sent back cooking tips that were somehow not condescending at all, just useful. Going to try again this weekend and actually put my phone in the other room this time.",
    "summary": "I burned chicken thighs while distracted by a work email, ate what I could salvage, and texted Maya about it. She sent useful cooking tips, and I plan to try again this weekend with my phone in the other room.",
    "mood": "frustrated",
    "secondaryMood": "connected",
    "areas": [
      "friends",
      "play"
    ],
    "tags": [
      "dinner",
      "texting"
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
          "play"
        ],
        "names": [],
        "offset": 0,
        "summary": "I tried to cook chicken thighs Maya's way, burned them while answering a work email, salvaged what I could, and plan to try again this weekend without my phone nearby.",
        "tags": [
          "dinner"
        ],
        "topic": "Burned chicken dinner"
      },
      {
        "areasRaw": [
          "friends"
        ],
        "names": [
          "Maya"
        ],
        "offset": 197,
        "summary": "I texted Maya about the burned chicken, and she replied with useful, non-condescending cooking tips.",
        "tags": [
          "texting",
          "dinner"
        ],
        "topic": "Cooking tips from Maya"
      }
    ],
    "opens": [
      {
        "about": [
          "Maya"
        ],
        "id": "t008",
        "text": "Try making the chicken thighs again this weekend with my phone in the other room"
      }
    ]
  },
  {
    "date": "2025-10-15T20:30",
    "title": "Told Kev about Maya",
    "text": "Trivia night, Quizteama Aguilera actually won for once, some fluke round on eighties movies that Omar somehow knew cold. Told Kev about Maya between rounds and he immediately wanted every detail, which is very Kev. He said bring her to trivia sometime so he and Jess can vet her, only half joking. Felt good saying her name out loud to someone other than Danny.",
    "summary": "I won trivia with Quizteama Aguilera after Omar knew an eighties-movies round cold. I told Kev about Maya and felt good saying her name out loud to someone other than Danny; Kev wants me to bring her to trivia so he and Jess can vet her.",
    "mood": "joyful",
    "secondaryMood": "connected",
    "areas": [
      "friends",
      "love"
    ],
    "tags": [
      "trivia night",
      "quizteama aguilera",
      "dating"
    ],
    "mentions": [
      {
        "kind": "project",
        "name": "Quizteama Aguilera"
      },
      {
        "kind": "person",
        "name": "Omar"
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
        "kind": "person",
        "name": "Jess"
      },
      {
        "kind": "person",
        "name": "Danny"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "friends"
        ],
        "names": [
          "Quizteama Aguilera",
          "Omar",
          "Kev"
        ],
        "offset": 0,
        "summary": "I won trivia with Quizteama Aguilera after Omar carried us through an eighties-movies round, then told Kev about Maya between rounds.",
        "tags": [
          "trivia night",
          "quizteama aguilera"
        ],
        "topic": "Trivia night win"
      },
      {
        "areasRaw": [
          "friends",
          "love"
        ],
        "names": [
          "Kev",
          "Maya",
          "Jess",
          "Danny"
        ],
        "offset": 121,
        "summary": "I enjoyed telling Kev about Maya and saying her name out loud to someone other than Danny, while Kev suggested bringing her to trivia for him and Jess to vet.",
        "tags": [
          "dating",
          "trivia night"
        ],
        "topic": "Telling Kev about Maya"
      }
    ],
    "opens": [
      {
        "about": [
          "Jess",
          "Kev",
          "Maya"
        ],
        "id": "t009",
        "text": "Bring Maya to trivia sometime"
      }
    ]
  },
  {
    "date": "2025-10-17T22:00",
    "title": "Date tomorrow",
    "text": "First actual date with Maya tomorrow, Nonna Pia's, her pick. Ironed a shirt properly this time instead of the shower trick. Keep rewriting what I'm going to say if she asks about work, since 'my new boss is rewriting my whole project' is not exactly a fun dating opener. Nervous in the good way. Pickles has no opinion on any of this and is asleep on my one clean shirt.",
    "summary": "I have my first actual date with Maya tomorrow at Nonna Pia's, her choice, and I prepared by ironing a shirt properly. I feel nervous in an excited way and am rewriting how I will talk about work if she asks.",
    "mood": "excited",
    "secondaryMood": "anxious",
    "areas": [
      "love",
      "work"
    ],
    "tags": [
      "dating",
      "dress code",
      "workplace",
      "quiet evening"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "place",
        "name": "Nonna Pia's"
      },
      {
        "kind": "other",
        "name": "Pickles"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "love"
        ],
        "names": [
          "Maya",
          "Nonna Pia's"
        ],
        "offset": 0,
        "summary": "I have my first actual date with Maya tomorrow at Nonna Pia's, her choice, and I ironed a shirt properly for it.",
        "tags": [
          "dating",
          "dress code"
        ],
        "topic": "First date preparation"
      },
      {
        "areasRaw": [
          "work",
          "love"
        ],
        "names": [],
        "offset": 124,
        "summary": "I am rewriting how to describe my work and new boss if Maya asks, since my current phrasing is not a good dating opener.",
        "tags": [
          "dating",
          "workplace"
        ],
        "topic": "Work conversation planning"
      },
      {
        "areasRaw": [
          "home"
        ],
        "names": [
          "Pickles"
        ],
        "offset": 296,
        "summary": "Pickles is asleep on my one clean shirt and has no opinion about the date.",
        "tags": [
          "quiet evening"
        ],
        "topic": "Pickles on my shirt"
      }
    ],
    "opens": [
      {
        "id": "t010",
        "text": "Rewrite what I'm going to say about work"
      }
    ],
    "resolves": [
      "t006"
    ],
    "touches": [
      "t007"
    ]
  },
  {
    "date": "2025-10-18T23:40",
    "title": "Nonna Pia's",
    "text": "First date with Maya at Nonna Pia's. Got there ten minutes early and sat at the bar pretending to check my phone. She showed up in scrubs from a shift that ran long, apologized for it like I would have cared, and ordered the cacio e pepe without opening the menu because apparently she always gets it here.\n\nTalked for three hours. She told me about a kid on her unit who calls her 'the plant lady' because she brings in new plants for the nurses' station every few months and half of them die within a week anyway. Told her about Danny and El Primo, about Pickles knocking one of my plants off the counter two weeks ago like he'd been rehearsing for this exact conversation. She laughed so hard at that one a couple at the next table looked over.\n\nDidn't bring up Greg or the roadmap once, which is probably a good sign about how the night was going. This felt like actual dating, not just two people who happen to text a lot. Walked her to the train after, didn't try to kiss her, just said I'd call her tomorrow and meant it. Drove home with the radio off the whole way, which I never do.",
    "summary": "I went on my first date with Maya at Nonna Pia's and felt like it was actual dating rather than just texting. I told her I'd call tomorrow and drove home feeling unusually absorbed in the night.",
    "mood": "excited",
    "secondaryMood": "hopeful",
    "areas": [
      "love"
    ],
    "tags": [
      "dating"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "place",
        "name": "Nonna Pia's"
      },
      {
        "kind": "person",
        "name": "Danny"
      },
      {
        "kind": "other",
        "name": "El Primo"
      },
      {
        "kind": "other",
        "name": "Pickles"
      },
      {
        "kind": "person",
        "name": "Greg"
      }
    ],
    "resolves": [
      "t007"
    ]
  },
  {
    "date": "2025-10-19T09:15",
    "title": "Morning after",
    "text": "Woke up still thinking about last night, which does not happen to me. Made coffee and just stood at the window for a while like an idiot with a mug. Texted Maya good morning, she was already on her way home from a shift and said she fell asleep on the train two stops past hers. Feels like real dating now, not just a good conversation at a party. Going to call this a good sign about how tired the good kind of tired can be.",
    "summary": "I woke up still thinking about Maya after last night, and our good-morning text made this feel like real dating rather than just a good conversation at a party.",
    "mood": "excited",
    "secondaryMood": "hopeful",
    "areas": [
      "love"
    ],
    "tags": [
      "dating",
      "texting"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      }
    ]
  },
  {
    "date": "2025-10-22T19:30",
    "title": "Second date",
    "text": "Second date with Maya, low key, just her place for pasta she actually cooked, her doing all the cooking while I mostly poured wine and stayed out of the way. Met the three dying plants in person, she's right, they all look terrible except the pothos on the windowsill that seems determined to survive out of spite. She asked more about work than I expected and actually understood what a reconciliation bug was without me explaining it twice, which never happens on a date. This is starting to feel like real dating. Stayed late enough that I had to sprint for the last reasonable train.",
    "summary": "I had a low-key second date with Maya at her place, where she cooked pasta and understood my work better than I expected. This is starting to feel like real dating, even if I had to sprint for the last reasonable train.",
    "mood": "hopeful",
    "secondaryMood": "connected",
    "areas": [
      "love",
      "work"
    ],
    "tags": [
      "dating"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      }
    ]
  },
  {
    "date": "2025-10-24T20:00",
    "title": "Metrics review",
    "text": "Greg's metrics reviews are getting more pointed. Today he pulled up my roadmap slide from three weeks ago next to today's numbers on the shared screen in front of the whole team, like a before and after ad for a diet product. Nothing wrong exactly, just a way of doing it that makes you feel like you're being graded in real time instead of just reporting in. Priya says he does this to everyone, that it's not personal. Doesn't feel like not personal.",
    "summary": "I felt exposed and graded when Greg compared my roadmap slide with today's numbers in front of the team. Priya says he does this to everyone, but it still didn't feel impersonal.",
    "mood": "insecure",
    "secondaryMood": "irritated",
    "areas": [
      "work"
    ],
    "tags": [
      "workplace",
      "roadmap"
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
    ]
  },
  {
    "date": "2025-10-26T13:30",
    "title": "Tacos and menu math",
    "text": "Sunday tacos at Taqueria Lupita, went through the actual numbers with Danny for the El Primo truck menu, cost per taco versus what he wants to charge, and it pencils out fine if he keeps it to three items like he wanted. He's genuinely relieved, kept saying 'so it's not insane' like he needed someone with a spreadsheet to tell him that. Told him about Maya properly this time, not the shorthand version, actual dating and everything. He wants to meet her before I even asked, obviously.",
    "summary": "I had Sunday tacos at Taqueria Lupita and worked through the El Primo's truck menu numbers with Danny, confirming that three items pencil out. I told him about dating Maya, and he wants to meet her.",
    "mood": "neutral",
    "secondaryMood": "connected",
    "areas": [
      "money",
      "love"
    ],
    "tags": [
      "tacos",
      "food truck",
      "menu planning",
      "dating"
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
        "name": "El"
      },
      {
        "kind": "person",
        "name": "Maya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "money",
          "work"
        ],
        "names": [
          "Taqueria Lupita",
          "Danny",
          "El Primo's truck",
          "El"
        ],
        "offset": 0,
        "summary": "I went through the El Primo's truck menu numbers with Danny and confirmed that three items keep the costs workable.",
        "tags": [
          "tacos",
          "food truck",
          "menu planning"
        ],
        "topic": "El Primo's menu numbers"
      },
      {
        "areasRaw": [
          "love"
        ],
        "names": [
          "Maya"
        ],
        "offset": 339,
        "summary": "I told Danny about my actual dating situation with Maya, and he wants to meet her.",
        "tags": [
          "dating"
        ],
        "topic": "Telling Danny about Maya"
      }
    ],
    "resolves": [
      "t001"
    ]
  },
  {
    "date": "2025-10-29T21:00",
    "title": "Priya's warning",
    "text": "Priya told me flat out today that the December launch is not happening without cutting the reconciliation testing window in half, and that cutting it is a bad idea. Said it in the hallway again, quietly, like she's trying not to be the one who said it on record. This whole roadmap decision was never really mine to make. I said I'd bring it to Greg. I have not brought it to Greg. Keep telling myself there's still time before it actually matters.",
    "summary": "I learned that the December launch would require an unwise cut to the reconciliation testing window, and I have not yet brought the roadmap decision to Greg.",
    "mood": "stressed",
    "secondaryMood": "conflicted",
    "areas": [
      "work"
    ],
    "tags": [
      "roadmap",
      "workplace"
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
    ],
    "opens": [
      {
        "about": [
          "Greg"
        ],
        "id": "t011",
        "text": "Bring the December launch decision to Greg"
      }
    ]
  },
  {
    "date": "2025-10-31T20:45",
    "title": "Halloween with the kids",
    "text": "Halloween in Naperville with Nina, Marcus, and the kids. Leo went as a stegosaurus, plates and tail and everything, and refused to take the head off even to eat a piece of candy, so Nina had to feed him bite by bite through the mouth hole like he was a baby bird. Ava was a ladybug for about twenty minutes before she decided she was actually a dog and started barking at trick-or-treaters on the porch. Marcus manned the grill even though it was forty degrees out, because apparently Halloween without grilled something isn't Halloween in that house. Told Nina about Maya, actual dating and everything, first time out loud to her. She said 'finally' before I even finished the sentence.",
    "summary": "I spent Halloween in Naperville with Nina, Marcus, and the kids, with elaborate costumes, porch barking, and grilling in the cold. I also told Nina that Maya and I are actually dating, and she said “finally.”",
    "mood": "joyful",
    "secondaryMood": "connected",
    "areas": [
      "play",
      "love"
    ],
    "tags": [
      "halloween",
      "dating",
      "trick-or-treating"
    ],
    "mentions": [
      {
        "kind": "place",
        "name": "Naperville"
      },
      {
        "kind": "person",
        "name": "Nina"
      },
      {
        "kind": "person",
        "name": "Marcus"
      },
      {
        "kind": "person",
        "name": "Leo"
      },
      {
        "kind": "person",
        "name": "Ava"
      },
      {
        "kind": "person",
        "name": "Maya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "play",
          "friends"
        ],
        "names": [
          "Naperville",
          "Nina",
          "Marcus",
          "Leo",
          "Ava"
        ],
        "offset": 0,
        "summary": "I spent Halloween in Naperville with Nina, Marcus, and the kids, including Leo's stegosaurus costume, Ava's shift from ladybug to dog, and Marcus grilling in the cold.",
        "tags": [
          "halloween",
          "trick-or-treating"
        ],
        "topic": "Halloween with friends"
      },
      {
        "areasRaw": [
          "love"
        ],
        "names": [
          "Nina",
          "Maya"
        ],
        "offset": 552,
        "summary": "I told Nina that Maya and I are actually dating, and she responded with “finally.”",
        "tags": [
          "dating"
        ],
        "topic": "Telling Nina about Maya"
      }
    ]
  },
  {
    "date": "2025-11-02T14:00",
    "title": "Quiet Sunday",
    "text": "Quiet one. Laundry, groceries, called Mom for the usual Sunday check-in where she asks if I'm eating enough vegetables and I lie a little. Maya's working a stretch of nights this week so we've mostly been texting between her naps. Pickles spent most of the afternoon in the laundry basket like it was built for him specifically.",
    "summary": "I had a quiet day with laundry, groceries, a Sunday check-in with Mom, and texting Maya between her naps. Pickles spent the afternoon in the laundry basket.",
    "mood": "calm",
    "secondaryMood": "content",
    "areas": [
      "home",
      "family"
    ],
    "tags": [
      "laundry",
      "groceries",
      "sunday check-in",
      "texting",
      "pet mishap"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Mom"
      },
      {
        "kind": "person",
        "name": "Maya"
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
        "names": [],
        "offset": 0,
        "summary": "I handled laundry and groceries during a quiet day.",
        "tags": [
          "laundry",
          "groceries"
        ],
        "topic": "Household errands"
      },
      {
        "areasRaw": [
          "family"
        ],
        "names": [
          "Mom"
        ],
        "offset": 38,
        "summary": "I called Mom for our usual Sunday check-in about eating vegetables.",
        "tags": [
          "sunday check-in"
        ],
        "topic": "Sunday call"
      },
      {
        "areasRaw": [
          "friends"
        ],
        "names": [
          "Maya"
        ],
        "offset": 139,
        "summary": "I have mostly been texting Maya between her naps while she works nights.",
        "tags": [
          "texting"
        ],
        "topic": "Maya's night shifts"
      },
      {
        "areasRaw": [
          "home"
        ],
        "names": [
          "Pickles"
        ],
        "offset": 231,
        "summary": "Pickles spent most of the afternoon in the laundry basket.",
        "tags": [
          "pet mishap"
        ],
        "topic": "Pickles in the basket"
      }
    ]
  },
  {
    "date": "2025-11-04T18:20",
    "title": "The schedule puzzle",
    "text": "Maya's on a run of night shifts this week which means our whole week is built around her sleep schedule instead of anything normal. Dinner at four in the afternoon so it counts as her breakfast, texting picking back up around midnight when she's on break, then radio silence until the next afternoon. Real dating apparently means learning somebody else's whole clock, and it doesn't actually bother me, it's just a puzzle to solve instead of an obstacle. Told her that and she said most guys don't make it past month two of the schedule. Planning to make it past month two.",
    "summary": "I’m adapting to Maya’s night-shift schedule and treating the disruption as a puzzle rather than an obstacle. I’m planning to make it past month two.",
    "mood": "confident",
    "secondaryMood": "content",
    "areas": [
      "love"
    ],
    "tags": [
      "dating"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      }
    ]
  },
  {
    "date": "2025-11-06T20:30",
    "title": "Trivia, no Maya yet",
    "text": "Trivia at The Brass Tap, Kev and Omar both asking when they finally get to meet Maya in person instead of hearing about her secondhand. Told them soon, dating a night shift nurse means logistics, but she's actually free next week for once. We came in second, lost the tiebreaker on a geography question none of us should have missed. Omar is taking it personally.",
    "summary": "I talked with Kev and Omar about finally meeting Maya, who is free next week despite her night-shift schedule. We came in second at trivia after losing a geography tiebreaker, and Omar is taking it personally.",
    "mood": "frustrated",
    "secondaryMood": "excited",
    "areas": [
      "friends",
      "love"
    ],
    "tags": [
      "trivia night",
      "dating"
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
        "kind": "person",
        "name": "Maya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "friends",
          "love"
        ],
        "names": [
          "Kev",
          "Omar",
          "Maya"
        ],
        "offset": 0,
        "summary": "I told Kev and Omar that Maya may be able to join trivia next week despite the logistics of dating a night shift nurse.",
        "tags": [
          "dating",
          "trivia night"
        ],
        "topic": "Maya meeting logistics"
      },
      {
        "areasRaw": [
          "friends"
        ],
        "names": [
          "Omar"
        ],
        "offset": 240,
        "summary": "I came in second with the group after losing a geography tiebreaker, and Omar is taking the result personally.",
        "tags": [
          "trivia night"
        ],
        "topic": "Trivia result"
      }
    ],
    "touches": [
      "t009"
    ]
  },
  {
    "date": "2025-11-08T19:00",
    "title": "Maya meets Kev and Jess",
    "text": "Maya finally met Kev and Jess, dinner at their place instead of trivia so it wasn't loud and chaotic for a first impression. Jess grilled her, gently, the way Jess grills everyone she actually likes. Maya held her own, told the leftover-roommate story again and it killed just as hard the second time. Kev pulled me aside doing dishes and just said 'yeah, okay, I get it' which from him is basically a standing ovation. Feels like real dating momentum now that she's met everyone. Drove home with Maya asleep against the window before we'd even hit the highway.",
    "summary": "Maya met Kev and Jess over dinner at their place, handled Jess’s questions well, and impressed Kev. I feel real dating momentum now that she has met everyone, and drove home with Maya asleep against the window.",
    "mood": "excited",
    "secondaryMood": "connected",
    "areas": [
      "love",
      "friends"
    ],
    "tags": [
      "dating",
      "dinner"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "person",
        "name": "Kev"
      },
      {
        "kind": "person",
        "name": "Jess"
      }
    ]
  },
  {
    "date": "2025-11-10T22:00",
    "title": "Late night, Payouts v2",
    "text": "Late one at the office, third this week, going through edge cases on Payouts v2 with the engineering team because the December launch date hasn't moved no matter how many times Priya says it out loud in roadmap meetings. Ben stayed late too without being asked, which I appreciated more than I said. Got home after eleven, ate cereal standing over the sink, went straight to bed. This is the part of the job I used to actually like, heads down solving something real. Just wish it wasn't happening on this timeline.",
    "summary": "I worked late again on Payouts v2 because the December launch timeline has not moved. I still value solving real problems, but the current timeline is wearing me down.",
    "mood": "stressed",
    "secondaryMood": "grateful",
    "areas": [
      "work",
      "health"
    ],
    "tags": [
      "workplace",
      "payouts v2",
      "roadmap",
      "late night"
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
        "name": "Ben"
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
          "Ben"
        ],
        "offset": 0,
        "summary": "I stayed late for the third time this week to work through Payouts v2 edge cases while the December launch timeline stayed fixed; Ben stayed late too, which I appreciated.",
        "tags": [
          "workplace",
          "payouts v2",
          "roadmap"
        ],
        "topic": "Late office work"
      },
      {
        "areasRaw": [
          "home",
          "health"
        ],
        "names": [],
        "offset": 300,
        "summary": "I got home after eleven, ate cereal over the sink, and went straight to bed.",
        "tags": [
          "late night"
        ],
        "topic": "Late-night routine"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [],
        "offset": 380,
        "summary": "I still like the heads-down work of solving something real, but not on this timeline.",
        "tags": [
          "workplace"
        ],
        "topic": "What I like about work"
      }
    ]
  },
  {
    "date": "2025-11-12T21:15",
    "title": "Cold run",
    "text": "Went running on the Lakefront Trail after work even though it was already dark and cold enough to regret it by block two. Needed it though, head was too full of Payouts v2 numbers to sit still at home. Pickles greeted me at the door like I'd been gone a year instead of an hour. Ordered dumplings, watched half a show, asleep by ten thirty for once.",
    "summary": "I went running on the Lakefront Trail after work to clear my head from Payouts v2 numbers, then came home to Pickles, ordered dumplings, watched half a show, and fell asleep by ten thirty.",
    "mood": "restless",
    "secondaryMood": "tired",
    "areas": [
      "health",
      "work"
    ],
    "tags": [
      "running",
      "payouts v2",
      "late night",
      "pet",
      "dumplings"
    ],
    "mentions": [
      {
        "kind": "place",
        "name": "Lakefront Trail"
      },
      {
        "kind": "project",
        "name": "Payouts v2"
      },
      {
        "kind": "other",
        "name": "Pickles"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "health",
          "work"
        ],
        "names": [
          "Lakefront Trail",
          "Payouts v2"
        ],
        "offset": 0,
        "summary": "I went running on the Lakefront Trail after work to clear my head from Payouts v2 numbers.",
        "tags": [
          "running",
          "payouts v2"
        ],
        "topic": "Running after work"
      },
      {
        "areasRaw": [
          "home"
        ],
        "names": [
          "Pickles"
        ],
        "offset": 202,
        "summary": "I came home to Pickles greeting me enthusiastically.",
        "tags": [
          "pet"
        ],
        "topic": "Coming home to Pickles"
      },
      {
        "areasRaw": [
          "play",
          "health"
        ],
        "names": [],
        "offset": 279,
        "summary": "I ordered dumplings, watched half a show, and went to sleep by ten thirty.",
        "tags": [
          "late night",
          "dumplings"
        ],
        "topic": "Quiet evening at home"
      }
    ]
  },
  {
    "date": "2025-11-15T13:00",
    "title": "Jess is pregnant",
    "text": "Jess told me at lunch today, she's pregnant, due in April. Kev apparently has known for two weeks and has been sitting on it, badly, according to Jess, who says he almost told the barista by accident. They're happy, nervous-happy, the good kind. Told Maya as soon as I got home and she got genuinely emotional about it, more than I expected, said something about how she sees so many kids at work but this one is going to actually be hers to spoil. Kept thinking the whole walk home about what kind of uncle I'm going to be to this baby. Bought a stupid tiny onesie on the way home before I could talk myself out of it.",
    "summary": "I learned that Jess is pregnant, due in April, and shared the news with Maya, who became emotional. I kept thinking about becoming an uncle and bought a tiny onesie for the baby.",
    "mood": "joyful",
    "secondaryMood": "excited",
    "areas": [
      "family"
    ],
    "tags": [
      "pregnancy",
      "baby",
      "family news",
      "gift",
      "baby news"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Jess"
      },
      {
        "kind": "person",
        "name": "Kev"
      },
      {
        "kind": "person",
        "name": "Maya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "family"
        ],
        "names": [
          "Jess",
          "Kev"
        ],
        "offset": 0,
        "summary": "I learned that Jess is pregnant, due in April, and that she and Kev are happy and nervous about it.",
        "tags": [
          "pregnancy",
          "baby news"
        ],
        "topic": "Jess's pregnancy news"
      },
      {
        "areasRaw": [
          "family"
        ],
        "names": [
          "Maya"
        ],
        "offset": 246,
        "summary": "I told Maya, thought about being an uncle, and bought a tiny onesie for the baby.",
        "tags": [
          "baby",
          "gift"
        ],
        "topic": "Becoming an uncle"
      }
    ]
  },
  {
    "date": "2025-11-17T13:10",
    "title": "Tacos, permit talk",
    "text": "Sunday tacos at Taqueria Lupita, Danny in a mood about the permit paperwork for El Primo's truck, some form he filled out wrong and now has to redo. Told him it's normal, every business I've ever read about had a permit story like this. He wasn't fully comforted but ate three tacos about it so I think he's fine. Asked when he's meeting Maya. Told him soon, actual dating soon, this time for real.",
    "summary": "I had Sunday tacos at Taqueria Lupita, talked Danny through redoing incorrect permit paperwork for El Primo's truck, and said he would meet Maya soon for actual dating.",
    "mood": "neutral",
    "areas": [
      "friends",
      "love"
    ],
    "tags": [
      "tacos",
      "dating",
      "workplace"
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
        "name": "El Primo's truck"
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
          "play"
        ],
        "names": [
          "Taqueria Lupita"
        ],
        "offset": 0,
        "summary": "I had tacos at Taqueria Lupita on Sunday.",
        "tags": [
          "tacos"
        ],
        "topic": "Sunday tacos"
      },
      {
        "areasRaw": [
          "friends",
          "work"
        ],
        "names": [
          "Danny",
          "El Primo's truck"
        ],
        "offset": 33,
        "summary": "Danny was upset about redoing permit paperwork for El Primo's truck, and I tried to reassure him while he ate three tacos.",
        "tags": [
          "workplace",
          "tacos"
        ],
        "topic": "Danny's permit paperwork"
      },
      {
        "areasRaw": [
          "love",
          "friends"
        ],
        "names": [
          "Danny",
          "Maya"
        ],
        "offset": 314,
        "summary": "I said Danny would meet Maya soon for actual dating, this time for real.",
        "tags": [
          "dating"
        ],
        "topic": "Danny meeting Maya"
      }
    ],
    "opens": [
      {
        "about": [
          "Danny",
          "Maya"
        ],
        "id": "t012",
        "text": "Have Danny meet Maya for actual dating"
      }
    ]
  },
  {
    "date": "2025-11-19T21:40",
    "title": "Greg overrides Priya",
    "text": "Priya made her case to Greg directly today about the roadmap, full scope cut proposal, real numbers on the testing window. Greg listened, nodded, thanked her for the thoroughness, and kept the December ninth launch date anyway. Said something about how 'shipping teaches you more than testing does.' Priya didn't say anything in the room. She found me after and just said 'write down that I said this would happen' which is not a sentence you want to hear from your engineering lead. I wrote it down.",
    "summary": "I recorded Priya’s warning after Greg kept the December ninth launch date despite her full-scope cut proposal and testing-window numbers.",
    "mood": "frustrated",
    "secondaryMood": "anxious",
    "areas": [
      "work"
    ],
    "tags": [
      "roadmap",
      "workplace"
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
    "date": "2025-11-21T20:00",
    "title": "Short one",
    "text": "Not much to say today. Work was work, long and grinding, nobody happy. Maya's on nights again. Skipped the gym, skipped dinner until nine, ate crackers over the sink and called it done. Need to figure out what cooking project to bring to Thanksgiving before Mom starts calling about it daily.",
    "summary": "I had a long, grinding day at work, skipped the gym and dinner, and ate crackers over the sink. I still need to choose a cooking project to bring to Thanksgiving before Mom starts calling about it daily.",
    "mood": "burnedOut",
    "secondaryMood": "tired",
    "areas": [
      "work",
      "health"
    ],
    "tags": [
      "workplace",
      "menu planning",
      "late night",
      "running",
      "dinner",
      "family news"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "person",
        "name": "Mom"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "work"
        ],
        "names": [],
        "offset": 23,
        "summary": "I had a long, grinding day at work where nobody seemed happy.",
        "tags": [
          "workplace"
        ],
        "topic": "Grinding workday"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Maya"
        ],
        "offset": 71,
        "summary": "I noted that Maya is working nights again.",
        "tags": [
          "late night"
        ],
        "topic": "Maya's night schedule"
      },
      {
        "areasRaw": [
          "health"
        ],
        "names": [],
        "offset": 95,
        "summary": "I skipped the gym and delayed dinner until nine, eating crackers over the sink.",
        "tags": [
          "running",
          "dinner"
        ],
        "topic": "Skipped exercise and dinner"
      },
      {
        "areasRaw": [
          "family"
        ],
        "names": [
          "Mom"
        ],
        "offset": 186,
        "summary": "I need to choose a cooking project to bring to Thanksgiving before Mom starts calling about it daily.",
        "tags": [
          "menu planning",
          "family news"
        ],
        "topic": "Thanksgiving cooking project"
      }
    ],
    "opens": [
      {
        "about": [
          "Mom"
        ],
        "id": "t013",
        "text": "Figure out what cooking project to bring to Thanksgiving"
      }
    ]
  },
  {
    "date": "2025-11-23T14:30",
    "title": "Maya's working Thursday",
    "text": "Maya's on shift Thanksgiving day, of course, hospitals don't close for turkey. She's fine about it, says she volunteered actually, trades it for Christmas later. This is what real dating a nurse looks like, apparently. I offered to skip Naperville and just do something quiet with her instead, she wouldn't hear of it, said go be with your family, we'll do our own thing this weekend. Told Mom it'll just be me this year. She asked four follow-up questions about Maya in a row before I could even answer the first one.",
    "summary": "Maya is working Thanksgiving at the hospital after volunteering for the shift, while I plan to be with my family and see her this weekend. Mom responded with several questions about Maya.",
    "mood": "connected",
    "secondaryMood": "reflective",
    "areas": [
      "love",
      "family"
    ],
    "tags": [
      "dating",
      "family news"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Maya"
      },
      {
        "kind": "place",
        "name": "Naperville"
      },
      {
        "kind": "person",
        "name": "Mom"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "love"
        ],
        "names": [
          "Maya",
          "Naperville"
        ],
        "offset": 0,
        "summary": "I adjusted my Thanksgiving plans around Maya's hospital shift, but she wants me to be with my family and for us to do our own thing this weekend.",
        "tags": [
          "dating"
        ],
        "topic": "Maya's Thanksgiving shift"
      },
      {
        "areasRaw": [
          "family"
        ],
        "names": [
          "Mom"
        ],
        "offset": 385,
        "summary": "I told Mom I would be on my own for Thanksgiving, and she immediately asked several questions about Maya.",
        "tags": [
          "family news"
        ],
        "topic": "Mom asks about Maya"
      }
    ]
  },
  {
    "date": "2025-11-25T19:00",
    "title": "Pie duty",
    "text": "Figured out the Thanksgiving thing, going to make the pumpkin pie from the recipe on the box because that's the extent of my cooking ability and everyone knows it. Bought the ingredients at the store by my place, the good kind of canned pumpkin Mom swears by. Also picked up a bottle of wine for Tía Carmen since she and Tío Ray usually come by Friday. Feels like a lot of errands for one pie.",
    "summary": "I decided to make the pumpkin pie from the box recipe for Thanksgiving, bought the ingredients and wine for Tía Carmen, and felt like it was a lot of errands for one pie.",
    "mood": "tired",
    "areas": [
      "family",
      "home"
    ],
    "tags": [
      "groceries",
      "dinner"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Mom"
      },
      {
        "kind": "person",
        "name": "Tía Carmen"
      },
      {
        "kind": "person",
        "name": "Tío Ray"
      }
    ],
    "resolves": [
      "t013"
    ]
  },
  {
    "date": "2025-11-27T22:30",
    "title": "Thanksgiving without Maya",
    "text": "Thanksgiving in Naperville, whole house full, Nina and Marcus and the kids, Leo running around narrating his own dinosaur battles and Ava refusing to sit still for longer than a minute. Tommy back from Champaign for the long weekend looking more tired than I expected finals season to make him. Dad carved the turkey like it was a surgical procedure, same as every year. My pie actually turned out fine, Mom said so twice which means she really means it once.\n\nAbuela asked about Maya twice before dinner even started, calling her 'la enfermera' since Mom apparently told her Maya's a nurse and that's just what she's decided to call her now. Wanted to know when she's meeting her, said it plain, no hinting. Told her soon, Abuela, I promise. She patted my hand and said something in Spanish about not waiting too long that I only half caught and didn't ask her to repeat.\n\nMissed Maya more than I expected to at a table this full. Called her during dessert, she was on a break, said the cafeteria was doing a weird sad turkey sandwich special and she'd take my pie over it any day. Drove back to the city late, full and a little wrung out in the good way these things always leave me.",
    "summary": "I spent Thanksgiving in Naperville with a full house of family and felt Maya’s absence more strongly than expected. Abuela wants to meet her soon, and I called Maya during dessert before driving back to the city.",
    "mood": "connected",
    "secondaryMood": "loved",
    "areas": [
      "family",
      "love"
    ],
    "tags": [
      "family news",
      "thanksgiving",
      "dating",
      "late night"
    ],
    "mentions": [
      {
        "kind": "event",
        "name": "Thanksgiving"
      },
      {
        "kind": "place",
        "name": "Naperville"
      },
      {
        "kind": "person",
        "name": "Nina"
      },
      {
        "kind": "person",
        "name": "Marcus"
      },
      {
        "kind": "person",
        "name": "Leo"
      },
      {
        "kind": "person",
        "name": "Ava"
      },
      {
        "kind": "person",
        "name": "Tommy"
      },
      {
        "kind": "place",
        "name": "Champaign"
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
        "name": "Abuela"
      },
      {
        "kind": "person",
        "name": "Maya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "family"
        ],
        "names": [
          "Naperville",
          "Nina",
          "Marcus",
          "Leo",
          "Ava",
          "Tommy",
          "Champaign",
          "Dad"
        ],
        "offset": 0,
        "summary": "I spent Thanksgiving surrounded by family, including Nina, Marcus, the kids, Tommy, Dad, and Mom.",
        "tags": [
          "family news",
          "thanksgiving"
        ],
        "topic": "Thanksgiving with family"
      },
      {
        "areasRaw": [
          "family",
          "love"
        ],
        "names": [
          "Abuela",
          "Maya",
          "Mom"
        ],
        "offset": 461,
        "summary": "Abuela directly asked when she would meet Maya, and I promised it would be soon.",
        "tags": [
          "family news",
          "dating"
        ],
        "topic": "Abuela asking about Maya"
      },
      {
        "areasRaw": [
          "love"
        ],
        "names": [
          "Maya"
        ],
        "offset": 874,
        "summary": "I called Maya during dessert and drove back to the city feeling full and pleasantly wrung out.",
        "tags": [
          "dating",
          "late night"
        ],
        "topic": "Calling Maya after dinner"
      }
    ],
    "opens": [
      {
        "about": [
          "Abuela",
          "Maya"
        ],
        "id": "t014",
        "text": "Have Maya meet my family"
      }
    ]
  },
  {
    "date": "2025-11-28T09:30",
    "title": "Day after",
    "text": "Slow morning, leftovers for breakfast standing at the counter, coffee too strong because I misjudged the scoop, my cooking clearly maxed out yesterday with the one pie. Mom already texted the family group chat with photos from yesterday including one deeply unflattering one of me mid-bite that I've asked her to delete at least six times over the years. Maya's off tonight, going to see her for real once I'm back in the city and not still smelling like turkey.",
    "summary": "I have a slow breakfast after yesterday's cooking, deal with an unflattering family photo Mom keeps sharing, and plan to see Maya once I am back in the city.",
    "mood": "irritated",
    "secondaryMood": "content",
    "areas": [
      "family",
      "love"
    ],
    "tags": [
      "coffee",
      "family news",
      "dating"
    ],
    "mentions": [
      {
        "kind": "person",
        "name": "Mom"
      },
      {
        "kind": "person",
        "name": "Maya"
      }
    ],
    "sections": [
      {
        "areasRaw": [
          "health"
        ],
        "names": [],
        "offset": 0,
        "summary": "I have a slow breakfast with leftovers and overly strong coffee after cooking a pie yesterday.",
        "tags": [
          "coffee"
        ],
        "topic": "slow breakfast"
      },
      {
        "areasRaw": [
          "family"
        ],
        "names": [
          "Mom"
        ],
        "offset": 169,
        "summary": "Mom shared family group-chat photos, including an unflattering picture of me that I have repeatedly asked her to delete.",
        "tags": [
          "family news"
        ],
        "topic": "family group chat"
      },
      {
        "areasRaw": [
          "love"
        ],
        "names": [
          "Maya"
        ],
        "offset": 355,
        "summary": "I plan to see Maya for real once I am back in the city and no longer smelling like turkey.",
        "tags": [
          "dating"
        ],
        "topic": "seeing Maya"
      }
    ]
  },
  {
    "date": "2025-11-29T20:00",
    "title": "Tacos, back to normal",
    "text": "Sunday tacos at Taqueria Lupita with Danny, back to the usual after a weekend of turkey. He finally got the permit paperwork sorted for El Primo's truck, filed it correctly this time, waiting on approval now which he says could take anywhere from two weeks to eternity depending on the mood of whoever reviews it. Told him about Abuela and 'la enfermera,' the nickname she's decided to use for Maya. He thought that was the funniest thing he's heard all month and is now going to call her that too, probably forever.",
    "summary": "I had Sunday tacos at Taqueria Lupita with Danny, caught up on the permit approval for El Primo's truck, and told him about Abuela's nickname for Maya. He found “la enfermera” hilarious and plans to use it indefinitely.",
    "mood": "joyful",
    "secondaryMood": "connected",
    "areas": [
      "friends",
      "work"
    ],
    "tags": [
      "tacos",
      "food truck",
      "sunday outing",
      "pet name"
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
        "name": "El Primo's truck"
      },
      {
        "kind": "person",
        "name": "Abuela"
      },
      {
        "kind": "other",
        "name": "la enfermera"
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
          "Taqueria Lupita",
          "Danny"
        ],
        "offset": 0,
        "summary": "I had Sunday tacos with Danny at Taqueria Lupita, returning to our usual after Thanksgiving weekend.",
        "tags": [
          "tacos",
          "sunday outing"
        ],
        "topic": "Sunday tacos with Danny"
      },
      {
        "areasRaw": [
          "work"
        ],
        "names": [
          "Danny",
          "El Primo's truck"
        ],
        "offset": 89,
        "summary": "Danny sorted and correctly filed the permit paperwork for El Primo's truck and is waiting for approval.",
        "tags": [
          "food truck"
        ],
        "topic": "Permit paperwork for truck"
      },
      {
        "areasRaw": [
          "family",
          "friends"
        ],
        "names": [
          "Abuela",
          "la enfermera",
          "Maya"
        ],
        "offset": 314,
        "summary": "I told Danny about Abuela calling Maya “la enfermera,” and he found it hilarious enough to adopt the nickname.",
        "tags": [
          "pet name"
        ],
        "topic": "The nickname la enfermera"
      }
    ],
    "opens": [
      {
        "about": [
          "El Primo's truck"
        ],
        "id": "t015",
        "text": "Waiting on approval for El Primo's truck permit"
      }
    ]
  },
  {
    "date": "2025-11-30T23:15",
    "title": "Nine days out",
    "text": "Nine days until the Payouts v2 launch, whether it's ready or not. Greg wants a daily standup just for this now, on top of everything else. Priya looks like she hasn't slept right in a week. I keep thinking about what she said, write down that I said this would happen, and wondering if I should be writing more things down too. Maya sent a picture of the ugliest pothos cutting she's ever propagated, said it's basically her now, one of my plants apparently a good influence. Small good thing in an otherwise long, grinding day. Going to bed early. Tomorrow is going to be worse.",
    "summary": "I am under heavy pressure from the Payouts v2 launch, the added daily standup, and concern about Priya's exhaustion and documenting what is happening. Maya's pothos message was a small good thing in a long, grinding day, and I am going to bed early before tomorrow gets worse.",
    "mood": "stressed",
    "secondaryMood": "tired",
    "areas": [
      "work"
    ],
    "tags": [
      "payouts v2",
      "workplace",
      "late night",
      "plants"
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
          "Payouts v2",
          "Greg",
          "Priya"
        ],
        "offset": 0,
        "summary": "I am facing a Payouts v2 launch in nine days, added daily standups, Priya's exhaustion, and uncertainty about documenting what is happening.",
        "tags": [
          "payouts v2",
          "workplace"
        ],
        "topic": "Payouts v2 pressure"
      },
      {
        "areasRaw": [
          "friends"
        ],
        "names": [
          "Maya"
        ],
        "offset": 328,
        "summary": "Maya sent an ugly pothos cutting photo and joked that it is basically her.",
        "tags": [
          "plants"
        ],
        "topic": "Maya's pothos"
      },
      {
        "areasRaw": [
          "work",
          "health"
        ],
        "names": [],
        "offset": 476,
        "summary": "I had one small good thing in an otherwise long, grinding day, and I am going to bed early because tomorrow is going to be worse.",
        "tags": [
          "late night"
        ],
        "topic": "End of a grinding day"
      }
    ]
  }
]
"""#
}
#endif
