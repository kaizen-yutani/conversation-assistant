# Interview Analysis Report

**Date:** December 16, 2025
**Duration:** ~25 minutes
**Position:** Technical role (likely backend/full-stack developer)

---

## Interview Summary

The interview covered multiple technical areas including:
- Current role and team structure
- Tech stack experience (React, Spring, AWS)
- AI/LLM integration experience
- SQL and database knowledge
- Programming languages familiarity

---

## Questions & Answers Analysis

### 1. Application & Current Role

**Interviewer:** "So what is your application? Like, this is all which you are talking about is the data. So what is the application? Who's the user of it?"

**Your Answer:** Mentioned React with Spring and AWS, working on automotive sales platform at AlmaMedia.

**AI Suggestion:** "Application: Real-world end-user system that consumes/benefits from the data"

**Analysis:**
- Answer was somewhat fragmented due to transcription cutting
- Could be clearer about the end-user value proposition
- Recommendation: Prepare a 30-second elevator pitch about your current project

---

### 2. Team Structure

**Interviewer:** "Okay, and what is your team structure?"

**Your Answer:** "We have like... 10 team members" (fragmented)

**AI Suggestion:** "Currently at AlmaMedia, working with a team on the automotive sales platform"

**Analysis:**
- Answer lacked detail about roles, responsibilities, and collaboration
- Recommendation: Structure answer as: "We have X developers, Y QA, working in [methodology], with [tools]"

---

### 3. Team Lead & Specifications

**Interviewer:** "And you have a team lead on top of you or like how who gives you the specifications?"

**Your Answer:** "Yes. Who gives specifications..." (fragmented)

**AI Suggestion:** "You typically have a team lead or manager who provides specifications and requirements"

**Analysis:**
- Answer was cut off/fragmented
- Should explain the workflow: requirements > specs > development > review

---

### 4. Data Structure Background

**Interviewer:** "And in terms of the data structure, right? So like you did like some kind of a degree course on the computer science or like you learned on the job?"

**Your Answer:** "No, mostly I'm self-taught and from work, but I have two certificates, one in Azure for basic, the basic Azure one, and then AWS AI practitioner, which I took a few months ago. Otherwise I'm like just mostly from Udemy from work from everywhere like but I have like more than 10 years experience of building those systems"

**Analysis:**
- Good mention of certifications (Azure, AWS AI Practitioner)
- 10+ years experience is strong
- Recommendation: Lead with experience years, then certifications, structure better

**Improved Answer:**
> "I have over 10 years of hands-on experience building production systems. While I'm primarily self-taught through practical work and continuous learning (Udemy courses, documentation), I've formalized my knowledge with Azure Fundamentals and AWS AI Practitioner certifications. My data structure knowledge comes directly from real-world problem solving."

---

### 5. Business Analytics Tools

**Interviewer:** "Have you worked on like some kind of a business analytic tools like reporting like Tableau or Microsoft Power BI something like that?"

**Your Answer:** "I think I worked with Microsoft Power BI... yeah for like visually visualizing platforms dashboards and stuff like this as far as I remember but we mostly use AWS for data pipelines that fits in analytics dashboards."

**Analysis:**
- Honest about uncertainty ("as far as I remember")
- Good pivot to AWS data pipelines
- Recommendation: Be more definitive or clearly state limited experience

---

### 6. AI/LLM Usage

**Interviewer:** "And you have like mentioned like you are working on the AI side also so which AI you are using?"

**Your Answer:** "Mostly Anthropics [Claude], I used also Gemini in Dago AI, we used it mostly for checking if some articles are credible or not credible, if the news are real or not real, and then it returns something to the person that is checking this specific article."

**AI Suggestion:** "Currently using LangChain and LangGraph for AI workflows at AlmaMedia"

**Analysis:**
- Good specific use case (article credibility checking)
- Named specific models (Claude, Gemini)
- Could mention the framework/architecture used

**Improved Answer:**
> "We primarily use Claude from Anthropic and Gemini. The main use case is content credibility checking - we have a system that analyzes articles to determine if news is real or potentially misinformation, then surfaces results to human reviewers. We've built this using LangChain for orchestration."

---

### 7. AI Integration with Applications

**Interviewer:** "Have you integrated with the code somehow? Like the application?"

**Your Answer:** "Yes yes yes we have one... we have [AWS] Lambdas with those [LLMs] and that's how we are like triggering requests to it and then it's returning the result from the AI like streaming with Java and Quarkus... but we had an issue with Lambdas and we also added WebSockets so the connection is not killed after specific time because some people like to deep research."

**AI Suggestion:** (garbled - "Yes, we've ll integratem")

**Analysis:**
- Excellent technical detail (Lambda, Quarkus, WebSockets)
- Good problem-solving example (timeout issue > WebSocket solution)
- Shows real-world experience with async/streaming patterns
- AI suggestion was broken - potential app issue

---

### 8. SQL Knowledge

**Interviewer:** "So SQL, we talked about it. You said like, you know, you're familiar, but it's a basic level..."

**Your Answer:** "I think most mostly on the middle part, like I know the concepts I understand, like SELECT, WHERE, JOINs, GROUP BY and so on."

**AI Suggestion:** "SQL at basic level is solid foundation - covers SELECT, WHERE, JOIN, GROUP BY"

**Analysis:**
- Honest self-assessment
- Could have been more confident
- Recommendation: Give specific examples of what you've done with SQL

---

### 9. SQL Indexes (Technical Deep Dive)

**Interviewer:** "Okay, indexes, like if you know what is the index?"

**Your Answer:** "Yeah, indexing is when you index the whole database so it knows where actually to find something and it's a little bit faster."

**Analysis:**
- Basic explanation, technically correct but simplified
- Recommendation: More precise definition would be stronger

**Better Answer:**
> "An index is a data structure that improves query performance by providing quick lookup paths to rows. It works similarly to a book's index - instead of scanning every page, you can jump directly to the relevant section."

---

### 10. Multiple Indexes on Table

**Interviewer:** "Can you have multiple indexes on the table?"

**Your Answer:** "Let me think about it. Yes, you can have multiple indexes in a single table. And I think each index picks up different queries and so on."

**AI Suggestion:** "Yes, you can have multiple indexes on a single table"

**Analysis:**
- Correct answer
- Good thinking out loud approach
- Could explain WHY you'd want multiple indexes

---

### 11. Index Trade-offs (Complex Question)

**Interviewer:** "But if you're saying like it stores the data in the same so that it can be faster, then how can you have two different indexes?"

**Your Answer:** "Like index updates cost and you can have multiple on a single table but each performance index is independent let's say on insert or update and like cons can be indexed separately."

**Analysis:**
- Identified the write cost trade-off (correct!)
- Answer was a bit scattered
- Shows understanding of indexing complexity

**Better Answer:**
> "Great question. Each index is a separate data structure pointing to the same underlying data. The trade-off is: every index speeds up reads but slows down writes because each INSERT/UPDATE must update all indexes. So you might have an index on `user_id` for one query pattern and another on `created_at` for time-based queries, but you pay the cost on every write."

---

### 12. Flight Data Indexing Strategy

**Interviewer:** "If you have like flight information... you are updating every time the flight is loading... So what will you choose as an index?"

**Your Answer:** "Multiple indexes on insert... index column, update frequently... index on flight ID, on timestamp, on aircraft... trade for fast retrieval during frequent uploads."

**Analysis:**
- Identified relevant columns (flight_id, timestamp, aircraft)
- Showed understanding of the trade-off
- Answer was fragmented

**Better Answer:**
> "For flight data with frequent writes, I'd be selective with indexes. I'd index `flight_id` as it's the primary lookup key. For time-based queries, a composite index on `(departure_time, status)` would help. But I'd avoid over-indexing given the write-heavy nature. Maybe use partitioning by date instead of heavy indexing, so older data is archived and current data stays fast."

---

### 13. C# and Other Languages

**Interviewer:** "Have you worked with like C sharp or any kind of other programming language?"

**Your Answer:** "With C Sharp I didn't work, I just have something like, I don't know, maybe just checked it out, but no, I didn't work with it. I worked with TypeScript, with Java, with Python and JavaScript."

**Analysis:**
- Honest about C# (didn't try to oversell)
- Listed relevant languages
- Good to mention transferable OOP skills

---

### 14. React Experience

**Interviewer:** "And how about like... basically React code?"

**Your Answer:** "Yeah, I think it's okay. It's just similar to other like Angular and stuff."

**Analysis:**
- Understated your experience
- Mentioned you work with React earlier
- Recommendation: Be more specific about React experience

---

## App Issues Identified

### 1. Garbled AI Suggestions
```
💡 Answer (Haiku 2327ms): • Yes, we've ll integratem
💡 Answer (Haiku 2498ms): • Yes, we've ll integratem
```
**Problem:** AI response was cut off/garbled multiple times.
**Fix:** Check streaming response handling, ensure complete responses before displaying.

### 2. Duplicate Processing
Multiple instances of the same transcription being classified:
```
📝 Transcription (377ms):  Okay, can you have multiple attacks on the table?
📝 Transcription (371ms):  Okay, can you have multiple indexes on the table?
```
**Problem:** Same audio segment processed twice with slightly different transcriptions.
**Fix:** Add deduplication logic or better segment boundaries.

### 3. Misclassification of Speakers
```
📝 [interviewee] Ok, and what is your team structure? We have like ...
```
**Problem:** Interviewer's question attributed to interviewee.
**Fix:** Improve speaker diarization, possibly use system audio vs mic audio distinction.

### 4. Fragmented Transcriptions
Long answers are getting split across multiple segments, making context hard to follow.
**Fix:** Consider longer silence thresholds for speech end detection, or buffer short segments.

### 5. Filler Detection Too Aggressive
```
🗣️ Filler word, ignoring: 'Got it, got it, got it, got it. Okay. And,'
```
**Problem:** Sometimes meaningful context is filtered out.
**Fix:** Consider context - fillers from interviewer might signal topic transition.

---

## Prompt Improvement Suggestions

### 1. Classification Prompt
Current classification seems to confuse interviewer/interviewee. Suggest adding:
- Speaker identification based on audio source (system vs mic)
- Role context in the prompt

### 2. Answer Generation Prompt
Some answers were garbled or incomplete. Suggest:
- Add minimum response length requirement
- Better error handling for truncated responses
- Validate response structure before displaying

### 3. Topic Continuity
When questions are incomplete, the buffering works but could be improved:
```
📦 Buffered: Yeah, like I come... triggers.
```
**Suggestion:** Include more context in the buffer-completion prompt.

---

## Display Improvements

1. **Timeline View:** Show Q&A pairs more clearly, group related exchanges
2. **Speaker Labels:** Clearly distinguish interviewer (system audio) vs you (mic)
3. **AI Confidence Score:** Show when AI suggestion might be unreliable
4. **Topic Tags:** Make topics clickable to filter related content
5. **Answer Quality Indicator:** Flag when your answer was fragmented

---

## Overall Assessment

**Strengths Shown:**
- 10+ years experience
- Strong AWS/cloud knowledge
- Real AI/LLM integration experience
- Honest about skill levels
- Good problem-solving examples (WebSocket solution)

**Areas to Improve:**
- SQL indexing explanations (practice more structured answers)
- Project elevator pitch (prepare 30-second summary)
- React experience articulation
- Reduce filler words ("like", "you know")

**Interview Rating:** 7/10
- Technical depth was demonstrated
- Communication could be more structured
- Showed practical experience over theoretical knowledge
