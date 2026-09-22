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
    "summary": "Greg started as the new VP of Product at Ledgerline and immediately reshuffled the roadmap.",
    "mood": "irritated",
    "secondaryMood": "uncertain",
    "areas": [
      "work"
    ],
    "tags": [
      "roadmap"
    ],
    "mentions": [
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Priya",
        "kind": "person"
      },
      {
        "name": "Ledgerline",
        "kind": "organization"
      }
    ]
  },
  {
    "date": "2025-09-24T20:30",
    "title": "Quizteama loses again",
    "text": "Trivia at The Brass Tap with Kev and Omar. Team name is still Quizteama Aguilera, we are still bad at sports questions and somehow worse at capitals. Came in fourth out of nine, which for us is basically winning. Kev bought the pitcher to celebrate not being last. Omar left early, has to go running in the morning now that his knee finally stopped bugging him. Good night anyway.",
    "summary": "I went to trivia at The Brass Tap with Kev and Omar and we came in fourth.",
    "mood": "content",
    "areas": [
      "friends"
    ],
    "tags": [
      "trivia",
      "running"
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
      }
    ]
  },
  {
    "date": "2025-09-26T18:00",
    "title": "Pickles versus the plant",
    "text": "Came home to potting soil all over the kitchen floor and Pickles sitting in the middle of it looking extremely pleased with himself. The plant did not survive. Neither did my patience for a minute. Cleaned it up, gave him tuna out of guilt even though it was clearly not deserved. Quiet Friday otherwise. Ordered pho, watched half a show, fell asleep on the couch.",
    "summary": "Pickles knocked over a plant and destroyed it, and I had a quiet Friday night in.",
    "mood": "content",
    "secondaryMood": "tired",
    "areas": [
      "home"
    ],
    "tags": [
      "pickles",
      "guilt"
    ],
    "mentions": []
  },
  {
    "date": "2025-09-28T13:15",
    "title": "Sunday tacos with Danny",
    "text": "Sunday tacos at Taqueria Lupita, the usual, al pastor and the green salsa that makes my nose run. Danny had his notebook out again, sketching menu ideas for El Primo's truck on a napkin. He wants three items max to start: al pastor, a vegetarian option, and horchata that's actually good instead of the syrupy stuff most trucks serve. Told him I'd help him put real numbers behind the menu instead of just vibes. He said that's why he loves me. Also said if I ever quit my job I'm required to work the window for free.",
    "summary": "I had Sunday tacos with Danny and offered to help him work out real numbers for El Primo's menu.",
    "mood": "content",
    "secondaryMood": "grateful",
    "areas": [
      "family"
    ],
    "tags": [
      "tacos",
      "truck"
    ],
    "mentions": [
      {
        "name": "Taqueria Lupita",
        "kind": "place"
      },
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
        "id": "c1-el-primo-menu",
        "text": "Help Danny finalize the taco truck menu",
        "about": [
          "Danny"
        ],
        "due": "2025-10-26"
      }
    ]
  },
  {
    "date": "2025-09-30T21:45",
    "title": "Payouts v2 moves up",
    "text": "Greg pulled Payouts v2 up to December in the roadmap review today. It was supposed to launch in March. Nobody asked engineering if that's realistic, they just asked me to make the slide work. Priya pulled me aside after and asked if I'd pushed back. I said I tried. I did not try very hard. Grabbing lunch with her this week to actually talk about it instead of doing it in a hallway.",
    "summary": "Greg moved the Payouts v2 launch up to December without checking with engineering first.",
    "mood": "stressed",
    "secondaryMood": "frustrated",
    "areas": [
      "work"
    ],
    "tags": [
      "roadmap",
      "launch"
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
        "name": "Priya",
        "kind": "person"
      }
    ],
    "opens": [
      {
        "id": "c1-priya-lunch",
        "text": "Get lunch with Priya to talk about the roadmap",
        "about": [
          "Priya"
        ],
        "due": "2025-10-08"
      }
    ]
  },
  {
    "date": "2025-10-02T08:20",
    "title": "Flat tire, borrowed drill",
    "text": "Bike had a flat again this morning, walked to the train instead and was fifteen minutes late on the commute. Need to actually fix the tire instead of pumping it every three days and pretending that's a solution. Also still have Dad's drill from putting up shelves in August, should get that back to him before he asks in that voice that isn't asking. Coffee at Café Olmo on the way in, same order, same barista who still doesn't know my name.",
    "summary": "My bike had another flat and I still need to return Dad's drill.",
    "mood": "tired",
    "secondaryMood": "irritated",
    "areas": [
      "home",
      "work"
    ],
    "tags": [
      "commute"
    ],
    "mentions": [
      {
        "name": "Dad",
        "kind": "person"
      },
      {
        "name": "Café Olmo",
        "kind": "place"
      }
    ],
    "opens": [
      {
        "id": "c1-fix-bike-tire",
        "text": "Fix the flat tire on my bike",
        "about": [],
        "due": "2025-10-15"
      },
      {
        "id": "c1-return-drill",
        "text": "Return Dad's drill",
        "about": [
          "Dad"
        ],
        "due": "2025-10-08"
      }
    ]
  },
  {
    "date": "2025-10-05T12:40",
    "title": "Tommy stress call",
    "text": "Tommy called during lunch, panicking about a stats final with finals week bearing down and grad school apps he hasn't started. Told him senior year is supposed to feel like this, that I panicked plenty at UIUC too and it worked out. He wasn't fully buying it. Promised to call Sunday night instead of during finals week chaos next time.",
    "summary": "Tommy called stressed about finals and grad school applications, and I tried to talk him down.",
    "mood": "reflective",
    "secondaryMood": "content",
    "areas": [
      "family"
    ],
    "tags": [
      "finals"
    ],
    "mentions": [
      {
        "name": "Tommy",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-10-06T19:00",
    "title": "New tire, evening run",
    "text": "Finally fixed the bike tire on my lunch break, guy at the shop did it in ten minutes and made me feel dumb for not doing it myself two weeks ago. Went running along the Lakefront Trail after work, first cold one of the season, could see my breath by the time I got back. Legs felt good. Ordered too much Thai food and ate all of it standing at the counter like an animal.",
    "summary": "I got the bike tire fixed and went for a cold evening run on the Lakefront Trail.",
    "mood": "content",
    "areas": [
      "health"
    ],
    "tags": [
      "running"
    ],
    "mentions": [
      {
        "name": "Lakefront Trail",
        "kind": "place"
      }
    ],
    "resolves": [
      "c1-fix-bike-tire"
    ]
  },
  {
    "date": "2025-10-08T13:00",
    "title": "Lunch with Priya",
    "text": "Got lunch with Priya finally, away from the office so we could actually talk about the roadmap. She thinks December is not happening without cutting scope hard, and that Greg either doesn't know that or doesn't care. Told her I'd raise it again but honestly I don't know how hard I can push this early with a new VP. Also swung by Naperville after work and dropped Dad's drill back off, he acted like he'd forgotten he ever lent it to me, which is very him.",
    "summary": "I got lunch with Priya to talk about the unrealistic roadmap and returned Dad's drill.",
    "mood": "conflicted",
    "secondaryMood": "tired",
    "areas": [
      "work",
      "family"
    ],
    "tags": [
      "roadmap"
    ],
    "mentions": [
      {
        "name": "Priya",
        "kind": "person"
      },
      {
        "name": "Greg",
        "kind": "person"
      },
      {
        "name": "Dad",
        "kind": "person"
      },
      {
        "name": "Naperville",
        "kind": "place"
      }
    ],
    "resolves": [
      "c1-priya-lunch",
      "c1-return-drill"
    ]
  },
  {
    "date": "2025-10-10T22:15",
    "title": "Party tomorrow",
    "text": "Rosa and Luis's engagement party is tomorrow at The Brass Tap. Danny's been texting the group chat about what to wear like it's a wedding and not forty people and a cake. Bought a card. Should probably iron a shirt instead of steaming it in the bathroom with the shower running like I always do.",
    "summary": "I'm getting ready for Rosa and Luis's engagement party tomorrow at The Brass Tap.",
    "mood": "content",
    "areas": [
      "family"
    ],
    "tags": [
      "party"
    ],
    "mentions": [
      {
        "name": "Rosa",
        "kind": "person"
      },
      {
        "name": "Luis",
        "kind": "person"
      },
      {
        "name": "The Brass Tap",
        "kind": "place"
      },
      {
        "name": "Danny",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-10-11T23:50",
    "title": "Rosa's engagement party",
    "text": "Rosa and Luis's engagement party at The Brass Tap, the whole family there plus half of Luis's hospital. Tía Carmen cried before anyone even gave a toast. Danny gave a toast that started as a joke about Luis's scrubs and ended with him actually choking up, which none of us expected from him. Tío Ray kept refilling everyone's glasses whether they wanted it or not.\n\nLuis introduced me to a friend of his from Lakeshore Children's, a nurse named Maya. We ended up talking for something like two hours, mostly near the plant Rosa had put on the bar as decoration that nobody was supposed to touch. She has three plants in her apartment that she's convinced are all dying and one that refuses to. We talked about bad roommates, she had one who used to eat other people's labeled leftovers and lie about it with a straight face. I talked too much about Payouts v2, which she somehow made sound interesting by asking good questions instead of nodding politely.\n\nGot her number before Danny dragged me over to take a group photo. Keep thinking about the way she laughed at the leftover story, this full unguarded thing, nothing careful about it. Might be reading into one good conversation. Don't care, it was a good conversation.",
    "summary": "I met Maya at Rosa and Luis's engagement party and we talked for two hours.",
    "mood": "excited",
    "secondaryMood": "hopeful",
    "areas": [
      "love",
      "family"
    ],
    "tags": [
      "party",
      "plants",
      "roommates"
    ],
    "mentions": [
      {
        "name": "Rosa",
        "kind": "person"
      },
      {
        "name": "Luis",
        "kind": "person"
      },
      {
        "name": "The Brass Tap",
        "kind": "place"
      },
      {
        "name": "Tía Carmen",
        "kind": "person"
      },
      {
        "name": "Danny",
        "kind": "person"
      },
      {
        "name": "Tío Ray",
        "kind": "person"
      },
      {
        "name": "Lakeshore Children's",
        "kind": "organization"
      },
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Payouts v2",
        "kind": "project"
      }
    ]
  },
  {
    "date": "2025-10-13T21:00",
    "title": "Texting Maya",
    "text": "Maya and I have been texting since Saturday, nothing heavy, just back and forth about her impossible dying plants and a show she's convinced I need to watch. She works nights most of the week which already sounds like it's going to be a scheduling puzzle, but she made a joke about it instead of apologizing for it, which I liked. Asked her to dinner. She said yes before I finished the sentence, or at least before I finished typing it.",
    "summary": "Maya and I have been texting and I asked her to dinner.",
    "mood": "hopeful",
    "secondaryMood": "excited",
    "areas": [
      "love"
    ],
    "tags": [
      "texting",
      "plants"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-10-14T19:30",
    "title": "Burnt dinner",
    "text": "Tried to make chicken thighs the way Maya described cooking hers, got distracted answering a work email and burned them black on one side. Salvaged what I could, ate it anyway out of stubbornness. Spent the rest of the night texting her about it, and she sent back cooking tips that were somehow not condescending at all, just useful. Going to try again this weekend and actually put my phone in the other room this time.",
    "summary": "I burned dinner trying to copy one of Maya's recipes and we texted about it.",
    "mood": "content",
    "secondaryMood": "frustrated",
    "areas": [
      "love",
      "home"
    ],
    "tags": [
      "cooking",
      "texting"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-10-15T20:30",
    "title": "Told Kev about Maya",
    "text": "Trivia night, Quizteama Aguilera actually won for once, some fluke round on eighties movies that Omar somehow knew cold. Told Kev about Maya between rounds and he immediately wanted every detail, which is very Kev. He said bring her to trivia sometime so he and Jess can vet her, only half joking. Felt good saying her name out loud to someone other than Danny.",
    "summary": "We won trivia and I told Kev about Maya for the first time.",
    "mood": "joyful",
    "areas": [
      "friends",
      "love"
    ],
    "tags": [
      "trivia"
    ],
    "mentions": [
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
      },
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
    "date": "2025-10-17T22:00",
    "title": "Date tomorrow",
    "text": "First actual date with Maya tomorrow, Nonna Pia's, her pick. Ironed a shirt properly this time instead of the shower trick. Keep rewriting what I'm going to say if she asks about work, since 'my new boss is rewriting my whole project' is not exactly a fun dating opener. Nervous in the good way. Pickles has no opinion on any of this and is asleep on my one clean shirt.",
    "summary": "I'm nervous about my first real date with Maya at Nonna Pia's tomorrow.",
    "mood": "anxious",
    "secondaryMood": "excited",
    "areas": [
      "love"
    ],
    "tags": [
      "dating",
      "pickles"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Nonna Pia's",
        "kind": "place"
      }
    ]
  },
  {
    "date": "2025-10-18T23:40",
    "title": "Nonna Pia's",
    "text": "First date with Maya at Nonna Pia's. Got there ten minutes early and sat at the bar pretending to check my phone. She showed up in scrubs from a shift that ran long, apologized for it like I would have cared, and ordered the cacio e pepe without opening the menu because apparently she always gets it here.\n\nTalked for three hours. She told me about a kid on her unit who calls her 'the plant lady' because she brings in new plants for the nurses' station every few months and half of them die within a week anyway. Told her about Danny and El Primo, about Pickles knocking one of my plants off the counter two weeks ago like he'd been rehearsing for this exact conversation. She laughed so hard at that one a couple at the next table looked over.\n\nDidn't bring up Greg or the roadmap once, which is probably a good sign about how the night was going. This felt like actual dating, not just two people who happen to text a lot. Walked her to the train after, didn't try to kiss her, just said I'd call her tomorrow and meant it. Drove home with the radio off the whole way, which I never do.",
    "summary": "I had our first real date with Maya at Nonna Pia's and it went great.",
    "mood": "joyful",
    "secondaryMood": "hopeful",
    "areas": [
      "love"
    ],
    "tags": [
      "dating",
      "plants",
      "pickles"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      },
      {
        "name": "Nonna Pia's",
        "kind": "place"
      },
      {
        "name": "Danny",
        "kind": "person"
      },
      {
        "name": "El Primo",
        "kind": "project"
      },
      {
        "name": "Greg",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-10-19T09:15",
    "title": "Morning after",
    "text": "Woke up still thinking about last night, which does not happen to me. Made coffee and just stood at the window for a while like an idiot with a mug. Texted Maya good morning, she was already on her way home from a shift and said she fell asleep on the train two stops past hers. Feels like real dating now, not just a good conversation at a party. Going to call this a good sign about how tired the good kind of tired can be.",
    "summary": "I woke up still thinking about my date with Maya and we texted good morning.",
    "mood": "content",
    "secondaryMood": "nostalgic",
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
    "date": "2025-10-22T19:30",
    "title": "Second date",
    "text": "Second date with Maya, low key, just her place for pasta she actually cooked, her doing all the cooking while I mostly poured wine and stayed out of the way. Met the three dying plants in person, she's right, they all look terrible except the pothos on the windowsill that seems determined to survive out of spite. She asked more about work than I expected and actually understood what a reconciliation bug was without me explaining it twice, which never happens on a date. This is starting to feel like real dating. Stayed late enough that I had to sprint for the last reasonable train.",
    "summary": "I had a second date with Maya at her place and met her houseplants.",
    "mood": "content",
    "secondaryMood": "grateful",
    "areas": [
      "love"
    ],
    "tags": [
      "dating",
      "plants",
      "cooking"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-10-24T20:00",
    "title": "Metrics review",
    "text": "Greg's metrics reviews are getting more pointed. Today he pulled up my roadmap slide from three weeks ago next to today's numbers on the shared screen in front of the whole team, like a before and after ad for a diet product. Nothing wrong exactly, just a way of doing it that makes you feel like you're being graded in real time instead of just reporting in. Priya says he does this to everyone, that it's not personal. Doesn't feel like not personal.",
    "summary": "Greg's metrics reviews are getting sharper and it's starting to feel personal.",
    "mood": "anxious",
    "secondaryMood": "irritated",
    "areas": [
      "work",
      "mind"
    ],
    "tags": [
      "roadmap",
      "metrics"
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
    "date": "2025-10-26T13:30",
    "title": "Tacos and menu math",
    "text": "Sunday tacos at Taqueria Lupita, went through the actual numbers with Danny for the El Primo truck menu, cost per taco versus what he wants to charge, and it pencils out fine if he keeps it to three items like he wanted. He's genuinely relieved, kept saying 'so it's not insane' like he needed someone with a spreadsheet to tell him that. Told him about Maya properly this time, not the shorthand version, actual dating and everything. He wants to meet her before I even asked, obviously.",
    "summary": "I helped Danny finish the real numbers for the El Primo menu and told him about Maya.",
    "mood": "content",
    "secondaryMood": "relieved",
    "areas": [
      "family",
      "love"
    ],
    "tags": [
      "tacos",
      "truck",
      "dating"
    ],
    "mentions": [
      {
        "name": "Taqueria Lupita",
        "kind": "place"
      },
      {
        "name": "Danny",
        "kind": "person"
      },
      {
        "name": "El Primo",
        "kind": "project"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ],
    "resolves": [
      "c1-el-primo-menu"
    ]
  },
  {
    "date": "2025-10-29T21:00",
    "title": "Priya's warning",
    "text": "Priya told me flat out today that the December launch is not happening without cutting the reconciliation testing window in half, and that cutting it is a bad idea. Said it in the hallway again, quietly, like she's trying not to be the one who said it on record. This whole roadmap decision was never really mine to make. I said I'd bring it to Greg. I have not brought it to Greg. Keep telling myself there's still time before it actually matters.",
    "summary": "Priya warned me again that the December launch date is not realistic.",
    "mood": "stressed",
    "secondaryMood": "guilty",
    "areas": [
      "work"
    ],
    "tags": [
      "launch",
      "roadmap"
    ],
    "mentions": [
      {
        "name": "Priya",
        "kind": "person"
      },
      {
        "name": "Greg",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-10-31T20:45",
    "title": "Halloween with the kids",
    "text": "Halloween in Naperville with Nina, Marcus, and the kids. Leo went as a stegosaurus, plates and tail and everything, and refused to take the head off even to eat a piece of candy, so Nina had to feed him bite by bite through the mouth hole like he was a baby bird. Ava was a ladybug for about twenty minutes before she decided she was actually a dog and started barking at trick-or-treaters on the porch. Marcus manned the grill even though it was forty degrees out, because apparently Halloween without grilled something isn't Halloween in that house. Told Nina about Maya, actual dating and everything, first time out loud to her. She said 'finally' before I even finished the sentence.",
    "summary": "I spent Halloween with Nina's family in Naperville and told Nina about Maya.",
    "mood": "joyful",
    "secondaryMood": "content",
    "areas": [
      "family"
    ],
    "tags": [
      "dating"
    ],
    "mentions": [
      {
        "name": "Nina",
        "kind": "person"
      },
      {
        "name": "Marcus",
        "kind": "person"
      },
      {
        "name": "Leo",
        "kind": "person"
      },
      {
        "name": "Ava",
        "kind": "person"
      },
      {
        "name": "Naperville",
        "kind": "place"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-11-02T14:00",
    "title": "Quiet Sunday",
    "text": "Quiet one. Laundry, groceries, called Mom for the usual Sunday check-in where she asks if I'm eating enough vegetables and I lie a little. Maya's working a stretch of nights this week so we've mostly been texting between her naps. Pickles spent most of the afternoon in the laundry basket like it was built for him specifically.",
    "summary": "Quiet Sunday with laundry, groceries, and the usual call with Mom.",
    "mood": "content",
    "areas": [
      "home",
      "family"
    ],
    "tags": [
      "texting",
      "pickles"
    ],
    "mentions": [
      {
        "name": "Mom",
        "kind": "person"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-11-04T18:20",
    "title": "The schedule puzzle",
    "text": "Maya's on a run of night shifts this week which means our whole week is built around her sleep schedule instead of anything normal. Dinner at four in the afternoon so it counts as her breakfast, texting picking back up around midnight when she's on break, then radio silence until the next afternoon. Real dating apparently means learning somebody else's whole clock, and it doesn't actually bother me, it's just a puzzle to solve instead of an obstacle. Told her that and she said most guys don't make it past month two of the schedule. Planning to make it past month two.",
    "summary": "Maya's night shifts make our schedule a puzzle but I don't mind it.",
    "mood": "hopeful",
    "secondaryMood": "content",
    "areas": [
      "love"
    ],
    "tags": [
      "dating",
      "texting",
      "sleep"
    ],
    "mentions": [
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-11-06T20:30",
    "title": "Trivia, no Maya yet",
    "text": "Trivia at The Brass Tap, Kev and Omar both asking when they finally get to meet Maya in person instead of hearing about her secondhand. Told them soon, dating a night shift nurse means logistics, but she's actually free next week for once. We came in second, lost the tiebreaker on a geography question none of us should have missed. Omar is taking it personally.",
    "summary": "Kev and Omar keep asking to meet Maya, and we lost trivia on a tiebreaker.",
    "mood": "content",
    "areas": [
      "friends"
    ],
    "tags": [
      "trivia",
      "dating"
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
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-11-08T19:00",
    "title": "Maya meets Kev and Jess",
    "text": "Maya finally met Kev and Jess, dinner at their place instead of trivia so it wasn't loud and chaotic for a first impression. Jess grilled her, gently, the way Jess grills everyone she actually likes. Maya held her own, told the leftover-roommate story again and it killed just as hard the second time. Kev pulled me aside doing dishes and just said 'yeah, okay, I get it' which from him is basically a standing ovation. Feels like real dating momentum now that she's met everyone. Drove home with Maya asleep against the window before we'd even hit the highway.",
    "summary": "Maya met Kev and Jess for the first time and it went really well.",
    "mood": "joyful",
    "secondaryMood": "relieved",
    "areas": [
      "love",
      "friends"
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
        "name": "Kev",
        "kind": "person"
      },
      {
        "name": "Jess",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-11-10T22:00",
    "title": "Late night, Payouts v2",
    "text": "Late one at the office, third this week, going through edge cases on Payouts v2 with the engineering team because the December launch date hasn't moved no matter how many times Priya says it out loud in roadmap meetings. Ben stayed late too without being asked, which I appreciated more than I said. Got home after eleven, ate cereal standing over the sink, went straight to bed. This is the part of the job I used to actually like, heads down solving something real. Just wish it wasn't happening on this timeline.",
    "summary": "Another late night working on Payouts v2 edge cases with the team.",
    "mood": "tired",
    "secondaryMood": "stressed",
    "areas": [
      "work"
    ],
    "tags": [
      "launch",
      "roadmap"
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
        "name": "Ben",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-11-12T21:15",
    "title": "Cold run",
    "text": "Went running on the Lakefront Trail after work even though it was already dark and cold enough to regret it by block two. Needed it though, head was too full of Payouts v2 numbers to sit still at home. Pickles greeted me at the door like I'd been gone a year instead of an hour. Ordered dumplings, watched half a show, asleep by ten thirty for once.",
    "summary": "I went for a cold run on the Lakefront Trail to clear my head about work.",
    "mood": "tired",
    "secondaryMood": "content",
    "areas": [
      "health"
    ],
    "tags": [
      "running",
      "pickles"
    ],
    "mentions": [
      {
        "name": "Lakefront Trail",
        "kind": "place"
      },
      {
        "name": "Payouts v2",
        "kind": "project"
      }
    ]
  },
  {
    "date": "2025-11-15T13:00",
    "title": "Jess is pregnant",
    "text": "Jess told me at lunch today, she's pregnant, due in April. Kev apparently has known for two weeks and has been sitting on it, badly, according to Jess, who says he almost told the barista by accident. They're happy, nervous-happy, the good kind. Told Maya as soon as I got home and she got genuinely emotional about it, more than I expected, said something about how she sees so many kids at work but this one is going to actually be hers to spoil. Kept thinking the whole walk home about what kind of uncle I'm going to be to this baby. Bought a stupid tiny onesie on the way home before I could talk myself out of it.",
    "summary": "Jess told me she's pregnant, due in April, and I told Maya when I got home.",
    "mood": "excited",
    "secondaryMood": "loved",
    "areas": [
      "friends",
      "love"
    ],
    "tags": [
      "baby"
    ],
    "mentions": [
      {
        "name": "Jess",
        "kind": "person"
      },
      {
        "name": "Kev",
        "kind": "person"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-11-17T13:10",
    "title": "Tacos, permit talk",
    "text": "Sunday tacos at Taqueria Lupita, Danny in a mood about the permit paperwork for El Primo's truck, some form he filled out wrong and now has to redo. Told him it's normal, every business I've ever read about had a permit story like this. He wasn't fully comforted but ate three tacos about it so I think he's fine. Asked when he's meeting Maya. Told him soon, actual dating soon, this time for real.",
    "summary": "Danny is stressed about El Primo's permit paperwork and still wants to meet Maya.",
    "mood": "content",
    "secondaryMood": "reflective",
    "areas": [
      "family"
    ],
    "tags": [
      "tacos",
      "truck",
      "dating"
    ],
    "mentions": [
      {
        "name": "Taqueria Lupita",
        "kind": "place"
      },
      {
        "name": "Danny",
        "kind": "person"
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
    "date": "2025-11-19T21:40",
    "title": "Greg overrides Priya",
    "text": "Priya made her case to Greg directly today about the roadmap, full scope cut proposal, real numbers on the testing window. Greg listened, nodded, thanked her for the thoroughness, and kept the December ninth launch date anyway. Said something about how 'shipping teaches you more than testing does.' Priya didn't say anything in the room. She found me after and just said 'write down that I said this would happen' which is not a sentence you want to hear from your engineering lead. I wrote it down.",
    "summary": "Greg overrode Priya's warnings and kept the December ninth launch date.",
    "mood": "anxious",
    "secondaryMood": "frustrated",
    "areas": [
      "work"
    ],
    "tags": [
      "launch",
      "roadmap"
    ],
    "mentions": [
      {
        "name": "Priya",
        "kind": "person"
      },
      {
        "name": "Greg",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-11-21T20:00",
    "title": "Short one",
    "text": "Not much to say today. Work was work, long and grinding, nobody happy. Maya's on nights again. Skipped the gym, skipped dinner until nine, ate crackers over the sink and called it done. Need to figure out what cooking project to bring to Thanksgiving before Mom starts calling about it daily.",
    "summary": "Long grinding workday, and I still need to figure out what to bring to Thanksgiving.",
    "mood": "tired",
    "secondaryMood": "irritated",
    "areas": [
      "work",
      "home"
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
        "name": "Mom",
        "kind": "person"
      }
    ],
    "opens": [
      {
        "id": "c1-thanksgiving-pie",
        "text": "Figure out what to bring to Thanksgiving",
        "about": [
          "Mom"
        ],
        "due": "2025-11-25"
      }
    ]
  },
  {
    "date": "2025-11-23T14:30",
    "title": "Maya's working Thursday",
    "text": "Maya's on shift Thanksgiving day, of course, hospitals don't close for turkey. She's fine about it, says she volunteered actually, trades it for Christmas later. This is what real dating a nurse looks like, apparently. I offered to skip Naperville and just do something quiet with her instead, she wouldn't hear of it, said go be with your family, we'll do our own thing this weekend. Told Mom it'll just be me this year. She asked four follow-up questions about Maya in a row before I could even answer the first one.",
    "summary": "Maya is working Thanksgiving day so I'll be going to Naperville without her.",
    "mood": "reflective",
    "secondaryMood": "disappointed",
    "areas": [
      "love",
      "family"
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
    "date": "2025-11-25T19:00",
    "title": "Pie duty",
    "text": "Figured out the Thanksgiving thing, going to make the pumpkin pie from the recipe on the box because that's the extent of my cooking ability and everyone knows it. Bought the ingredients at the store by my place, the good kind of canned pumpkin Mom swears by. Also picked up a bottle of wine for Tía Carmen since she and Tío Ray usually come by Friday. Feels like a lot of errands for one pie.",
    "summary": "I decided to bring a box-mix pumpkin pie to Thanksgiving and bought the ingredients.",
    "mood": "content",
    "areas": [
      "family",
      "home"
    ],
    "tags": [
      "cooking"
    ],
    "mentions": [
      {
        "name": "Mom",
        "kind": "person"
      },
      {
        "name": "Tía Carmen",
        "kind": "person"
      },
      {
        "name": "Tío Ray",
        "kind": "person"
      }
    ],
    "resolves": [
      "c1-thanksgiving-pie"
    ]
  },
  {
    "date": "2025-11-27T22:30",
    "title": "Thanksgiving without Maya",
    "text": "Thanksgiving in Naperville, whole house full, Nina and Marcus and the kids, Leo running around narrating his own dinosaur battles and Ava refusing to sit still for longer than a minute. Tommy back from Champaign for the long weekend looking more tired than I expected finals season to make him. Dad carved the turkey like it was a surgical procedure, same as every year. My pie actually turned out fine, Mom said so twice which means she really means it once.\n\nAbuela asked about Maya twice before dinner even started, calling her 'la enfermera' since Mom apparently told her Maya's a nurse and that's just what she's decided to call her now. Wanted to know when she's meeting her, said it plain, no hinting. Told her soon, Abuela, I promise. She patted my hand and said something in Spanish about not waiting too long that I only half caught and didn't ask her to repeat.\n\nMissed Maya more than I expected to at a table this full. Called her during dessert, she was on a break, said the cafeteria was doing a weird sad turkey sandwich special and she'd take my pie over it any day. Drove back to the city late, full and a little wrung out in the good way these things always leave me.",
    "summary": "I spent Thanksgiving in Naperville without Maya, and Abuela kept asking about 'la enfermera.'",
    "mood": "grateful",
    "secondaryMood": "nostalgic",
    "areas": [
      "family",
      "love"
    ],
    "tags": [
      "pie"
    ],
    "mentions": [
      {
        "name": "Naperville",
        "kind": "place"
      },
      {
        "name": "Nina",
        "kind": "person"
      },
      {
        "name": "Marcus",
        "kind": "person"
      },
      {
        "name": "Leo",
        "kind": "person"
      },
      {
        "name": "Ava",
        "kind": "person"
      },
      {
        "name": "Tommy",
        "kind": "person"
      },
      {
        "name": "Dad",
        "kind": "person"
      },
      {
        "name": "Mom",
        "kind": "person"
      },
      {
        "name": "Abuela",
        "kind": "person"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-11-28T09:30",
    "title": "Day after",
    "text": "Slow morning, leftovers for breakfast standing at the counter, coffee too strong because I misjudged the scoop, my cooking clearly maxed out yesterday with the one pie. Mom already texted the family group chat with photos from yesterday including one deeply unflattering one of me mid-bite that I've asked her to delete at least six times over the years. Maya's off tonight, going to see her for real once I'm back in the city and not still smelling like turkey.",
    "summary": "Slow morning after Thanksgiving, and I'm heading back to see Maya tonight.",
    "mood": "content",
    "secondaryMood": "tired",
    "areas": [
      "family",
      "home"
    ],
    "tags": [
      "cooking"
    ],
    "mentions": [
      {
        "name": "Mom",
        "kind": "person"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-11-29T20:00",
    "title": "Tacos, back to normal",
    "text": "Sunday tacos at Taqueria Lupita with Danny, back to the usual after a weekend of turkey. He finally got the permit paperwork sorted for El Primo's truck, filed it correctly this time, waiting on approval now which he says could take anywhere from two weeks to eternity depending on the mood of whoever reviews it. Told him about Abuela and 'la enfermera,' the nickname she's decided to use for Maya. He thought that was the funniest thing he's heard all month and is now going to call her that too, probably forever.",
    "summary": "Back to Sunday tacos with Danny, whose truck permit is finally filed correctly.",
    "mood": "content",
    "secondaryMood": "joyful",
    "areas": [
      "family"
    ],
    "tags": [
      "tacos",
      "truck"
    ],
    "mentions": [
      {
        "name": "Taqueria Lupita",
        "kind": "place"
      },
      {
        "name": "Danny",
        "kind": "person"
      },
      {
        "name": "El Primo",
        "kind": "project"
      },
      {
        "name": "Abuela",
        "kind": "person"
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  },
  {
    "date": "2025-11-30T23:15",
    "title": "Nine days out",
    "text": "Nine days until the Payouts v2 launch, whether it's ready or not. Greg wants a daily standup just for this now, on top of everything else. Priya looks like she hasn't slept right in a week. I keep thinking about what she said, write down that I said this would happen, and wondering if I should be writing more things down too. Maya sent a picture of the ugliest pothos cutting she's ever propagated, said it's basically her now, one of my plants apparently a good influence. Small good thing in an otherwise long, grinding day. Going to bed early. Tomorrow is going to be worse.",
    "summary": "Nine days from the Payouts v2 launch and the pressure at work is climbing fast.",
    "mood": "anxious",
    "secondaryMood": "tired",
    "areas": [
      "work",
      "love"
    ],
    "tags": [
      "launch",
      "plants"
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
      },
      {
        "name": "Maya",
        "kind": "person"
      }
    ]
  }
]
"""#
}
#endif
