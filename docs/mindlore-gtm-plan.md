# Mindlore Go-To-Market Plan

This is the marketing and launch plan for Mindlore. It works in two ways: as a reference for Nate, and as a build spec for Claude Code (the "Builds" sections are written as tasks with acceptance criteria).

## 1. Goal and the math

1. **Goal**
    - $120k/year in subscription revenue.
2. **What that takes at current pricing** ($7.99/month, $49.99/year, 14-day trial, Apple Small Business Program at 15%)
    - With a mix of about 60% annual and 40% monthly, 1,000 subscribers is roughly $68k gross, or about $58k net.
    - $120k gross takes roughly **1,800–2,000 paying subscribers**. That is the real target.
3. **The funnel that implies**
    - With a 10% download-to-paid rate, that's about 20k downloads. At a 5% rate, it's about 40k. Retention and annual plans decide how much of that sticks.

## 2. Positioning

1. **The wedge**
    - **The Mind map**: a living graph of the people, places and projects in your life, with a one-year replay.
    - **"Not your therapist"**: most of the category sells therapist-designed prompts or AI coaching. Mindlore doesn't talk back. It listens, remembers and shows you patterns.
    - **Private by default**: everything stays on-device in the free tier.
2. **Lines to use everywhere, word for word**
    - One-liner: "It doesn't talk back. It remembers."
    - Descriptor: "A private voice journal that maps the people in your life."
    - Pro pitch: "Your journal is always yours. Pro adds the bigger brain that reads it."
3. **Guardrails**
    - No therapy, health or mental-health outcome claims, anywhere.
    - No fake reviews, fake testimonials, or AI avatars presented as real users.
    - Always disclose that Nate is the builder when posting in communities.

## 3. Competitors to position against

1. **Rosebud**: chat-based AI journal with therapist-designed prompts, $12.99/month or $9.99/month billed annually.
2. **Life Note**: AI mentors modeled on historical figures, $10.99/month or $99.99/year.
3. **Reflection**, **Mindsera**, **Day One**, **Stoic**, **Reflectly**, and newer apps like Claire and The Architect.
4. **Mindlore's gap**: voice-first capture + a relationship graph + on-device privacy + not a chatbot. None of the above combines all four.

## 4. Timeline

The launch date is **Tuesday, Nov 17, 2026**. It avoids Thanksgiving week (Nov 26) and gives six weeks of ratings before the January journaling spike.

1. **Phase 0: Foundations (Sep 25 – Oct 2)**
    - Paid Apple Developer account and Small Business Program enrollment.
    - Domain (mindlore.app or similar) plus a privacy policy page.
    - Lock pricing and the Pro/Free split (see the Pro + proxy plan).
2. **Phase 1: Beta and assets (Oct 2 – Oct 23)**
    - TestFlight beta with 50–100 testers from X, friends, r/Journaling and r/iOSBeta.
    - Ask every tester: "What did your Mind map show you that surprised you?" Save the answers (with permission) as hook material.
    - Build the landing page (Build A), the video template (Build B), and the AI visibility tracker (Build D).
    - Start building in public on X, 2–3 posts a week.
3. **Phase 2: Pre-launch (Oct 26 – Nov 13)**
    - Post 1–3 short videos a day on TikTok and Reels.
    - Finalize the App Store listing (section 5) and publish the first 3 web pages (section 6).
    - Participate genuinely on Reddit a few times a week.
    - **Submit for App Review by Fri, Nov 6**, with manual release.
    - Prepare the Product Hunt page, the Show HN post, the waitlist email, and the launch video.
4. **Phase 3: Launch week (Nov 16 – Nov 20)**
    - **Monday**: release the app. Beta testers download it and leave honest ratings.
    - **Tuesday**: Product Hunt at 12:01am Pacific, Show HN in the morning, email the waitlist, post an X launch thread, and post in r/Journaling if its rules allow. Reply to everything all day.
    - **Wednesday to Friday**: post the best-performing hooks, answer reviews, and fix launch bugs.
5. **Phase 4: Iterate (Nov 23 – Dec 18)**
    - Read the funnel in RevenueCat and fix the weakest step first.
    - Start Apple Search Ads at $5/day on the top 3 keywords.
    - Pitch the authors of "best AI journaling app" lists. Publish 2 web pages a week.
    - **By mid-December**, submit the January listing update and an In-App Event (App Review slows around the holidays).
6. **Phase 5: The January push (Dec 28 – Jan 31)**
    - Run a "30 days of talking it out" challenge where the payoff is seeing your own map.
    - Scale the Apple Search Ads keywords and video formats that are working.
    - Push for ratings through the in-app prompt.

## 5. App Store optimization

1. **Metadata**
    - Title: "Mindlore: Voice Journal & Diary"
    - Subtitle: "Private AI journal, on device"
    - Keyword field (100 characters, no repeats of title words): `talk,audio,reflection,mood,gratitude,memoir,people,relationships,notebook,prompts,daily`
    - The description isn't indexed on iOS, so write it for humans and lead with the wedge.
2. **Screenshots, in order**
    - (1) "Just talk. It becomes a journal." (2) The Mind map. (3) Ask, with cited entries. (4) "Stays on your phone."
    - Caption them with your keywords, since Apple's AI-generated tags draw on screenshots.
3. **Custom Product Pages**
    - One each for "voice journal", "private journal" and "Day One alternative", each with screenshots matched to that search.
4. **Ratings**
    - Prompt after the first Reflect summary or first Ask answer. Reply to every 1–3 star review within 24 hours.
5. **Seasonality**
    - January is the peak for journaling searches. Refresh metadata and screenshots every quarter, and in December for January.

## 6. Web SEO and AI visibility (getting recommended by ChatGPT and Claude)

1. **Site pages**
    - The home page (Build A), plus pages that answer real questions:
    - "Mindlore vs Rosebud", "Mindlore vs Day One", "Best private journaling apps", "Voice journaling: how and why", "AI journal that isn't a chatbot".
2. **How to write them**
    - Open with a direct answer in the first 50–80 words: the category, who it's for, what it does, and a limitation.
    - Make honest comparisons with real prices, and date-stamp them.
    - Refresh every page monthly. Freshness matters a lot to AI citations.
3. **Off-site mentions (the part that actually moves AI recommendations)**
    - **Reddit**: genuine answers in r/Journaling, r/productivity, r/iphone and r/ADHD. Mention Mindlore only when it fits, and always disclose you built it.
    - **"Best of" lists**: email the authors of existing roundups and ask to be included.
    - **Directories**: Product Hunt, AlternativeTo, and similar sites.
4. **Deprioritized**
    - llms.txt and schema markup: add them once as hygiene, but don't expect them to move citations.
5. **Expectations**
    - Content changes take 1–3 months to show up in AI answers, and off-site mentions take 6+ months.

## 7. Short-form video

1. **Formats**
    - **Map reveal**: a hook line, then the one-year Mind graph replay, then an end card.
    - **Slideshow listicles**: value first, with one soft mention of Mindlore in the middle, never opening with the app name.
    - **Founder clips**: Nate talking about why he built it. Real people beat AI avatars for trust.
2. **Hook directions**
    - "I journaled out loud for a year. This is a map of everyone I talked about."
    - "My journal noticed I stopped mentioning my best friend in March."
    - "Not a therapist. Not a chatbot. Just a journal that remembers."
3. **Cadence**
    - 1–3 posts a day. After two weeks, keep the formats with the most saves and shares.
4. **AI B-roll**
    - Use Higgsfield (Veo 3.1 for realism, Kling 3.0 for people) only for mood shots around a real screen recording. Never as a fake testimonial, and disclose synthetic media where platforms require it.

## 8. Paid acquisition

1. **Apple Search Ads**
    - Start only after launch, once the product page converts well.
    - $5/day on the top 3 keywords, using the new-account starter credit.
    - Connect it to RevenueCat and judge keywords by paying subscribers, not installs.
2. **Everything else** (TikTok and Meta ads): not until a video format has proven itself organically.

## 9. Builds for Claude Code

Each build is its own small project. Work on them one at a time.

### Build A: Landing page

1. **Stack**
    - Next.js or Astro on Vercel, with Motion for animation (install Motion's AI Kit skill and MCP first).
2. **Sections**
    - Hero with a scroll-linked Mind graph that builds node by node, then "Not your therapist, not a chatbot", a privacy section, a feature trio (Capture, Mind, Ask), pricing, an answer-first FAQ, and a waitlist.
    - After launch, the waitlist becomes the App Store link.
3. **Requirements**
    - All copy is server-rendered text; nothing important lives only in canvas or animation.
    - Mobile-first. Respect `prefers-reduced-motion`. Include Open Graph images, a sitemap, and basic Organization and SoftwareApplication schema.
    - Waitlist emails are stored in Supabase.
4. **Acceptance**
    - Lighthouse 90+ on mobile, the page works with JavaScript disabled (minus the animations), a MotionScore audit grade of A or better, and a waitlist submission lands in Supabase.

### Build B: Video template (Remotion)

1. **Setup**
    - A Remotion project with the official Remotion skill for Claude Code.
2. **Footage**
    - Record the Mind graph year replay from the `-seedStoryJournal` data in the simulator with `xcrun simctl io booted recordVideo`.
3. **Composition**
    - 9:16, 15 seconds: hook text (0–3s), the graph replay with zooms and captions (3–12s), and an end card ("Mindlore. It remembers.") (12–15s).
    - Driven by props: hook text, caption lines, and accent color.
4. **Batch rendering**
    - `render-batch hooks.json` renders one MP4 per hook.
5. **Acceptance**
    - One command renders 10 variants from a JSON file, and text stays readable at phone size.

### Build C: Hook miner (weekly agent)

1. **Inputs**
    - New posts and comments in r/Journaling and related subreddits; competitors' 1–3 star App Store reviews (Rosebud, Day One, Reflection, Mindsera, Life Note).
2. **Output**
    - A weekly `hooks-YYYY-MM-DD.json` with 10 hooks across two angles: map reveal and "doesn't talk back". Each hook cites the post or review that inspired it, and the file drops straight into Build B.
3. **Rules**
    - Read-only. It never posts or comments anywhere.
4. **Acceptance**
    - A weekly run produces valid JSON that Build B renders without edits.

### Build D: AI visibility tracker (weekly)

1. **What it does**
    - A Go job that sends ~20 prompts (e.g. "best voice journaling app for iPhone", "private AI journal", "journal app that isn't a chatbot", "Rosebud alternatives") to the ChatGPT, Claude, Gemini and Perplexity APIs.
2. **What it records**
    - Whether Mindlore is mentioned, its position in the list, which competitors are named, and which sources are cited. Stored in Supabase.
3. **Output**
    - A weekly summary of mention rate per engine over time, the top cited sources to target for off-site mentions, and new competitors appearing.
4. **Acceptance**
    - A baseline run works before launch, and the weekly schedule is set up.

### Build E: Content refresher

1. **Monthly job**
    - Re-checks competitor prices and features against their public pages, flags anything stale on Mindlore's comparison pages, and drafts updates as a pull request for Nate to review.
2. **Acceptance**
    - It opens a PR with specific diffs and sources for each change.

### Build F: Reddit radar

1. **What it does**
    - Flags new threads in target subreddits where someone asks for a journaling app recommendation or describes the problem Mindlore solves. It sends a short daily digest with links.
2. **Rules**
    - It never drafts, posts or comments. Nate writes every reply himself.
3. **Acceptance**
    - The daily digest arrives with relevant threads and few false positives.

## 10. Metrics and targets

1. **Numbers to watch weekly**
    - Product page conversion rate (App Store Connect).
    - Trial-start rate, trial-to-paid rate, and download-to-paid rate (RevenueCat).
    - Week-1 and week-4 retention.
    - AI mention rate (Build D).
    - Video saves and shares per post, and waitlist size before launch.
2. **Targets** (markers for whether things are working, not predictions)
    - Launch day: 300+ waitlist signups.
    - End of December: 100 paying subscribers, product page conversion of 30%+.
    - End of January: 300 paying subscribers, and Mindlore mentioned in at least a few tracked AI prompts.
    - Mid-2027: 1,000 paying subscribers. By end of 2027: ~2,000 (the $120k run rate).

## 11. Weekly rhythm after launch (about 5–8 hours)

1. **Monday**: review Build D, the funnel numbers and costs, and pick one thing to fix.
2. **Tuesday**: review the hook bank from Build C and render 5–10 videos with Build B.
3. **Wednesday**: publish or refresh one web page (with help from Build E).
4. **Throughout the week**: post daily (scheduled), reply to threads from Build F, and answer reviews within 24 hours.
