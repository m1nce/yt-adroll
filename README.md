# MGT 159T Final Project — YouTube Mid-Roll Ad Threshold RDD

A research proposal and analysis plan for measuring the behavioral distortion caused by YouTube's minimum-length rule for mid-roll advertisements.

## Research Question

Has YouTube's minimum-length rule for mid-roll ads caused creators to strategically lengthen their videos to cross the eligibility threshold (10:00 before July 27, 2020; 8:00 after), and if so, how large is the distortion?

**Method:** Regression Discontinuity Design (RDD) with the McCrary density test as the primary specification, plus a difference-in-differences robustness check around the 2020 policy switch.

## Repository Layout

| Path | Contents |
|---|---|
| `project_question/` | Assignment prompt, dataset description, and the research-proposal deliverable (`deliverable.md`, `.Rmd`, `.pdf`) |
| `plan_of_attack/` | Group plan-of-attack document (PDF) |
| `docs/` | Working specs and supporting documentation |

## Data

- **Source:** YouTube Data API v3, supplemented by SocialBlade / NoxInfluencer leaderboards for channel sampling.
- **Scope:** ~200K–400K videos from ~1,500 English-language channels (10K–1M subscribers), uploaded January 2018 – December 2023.
- **Categories:** Gaming, People & Blogs, Education, Howto & Style, Entertainment, Comedy. Music, News, Film & Animation, Sports, and Trailers are excluded because their length is structurally determined.
- **Running variable:** `duration_sec`.

## Design Summary

- **Cutoff 1:** 10:00 (600s) — pre-July 27, 2020.
- **Cutoff 2:** 8:00 (480s) — post-July 27, 2020.
- **Primary outcome:** density discontinuity at each cutoff (manipulation / strategic padding).
- **Secondary outcomes:** views, likes, comments above vs. below each cutoff.
- **Placebos:** density tests at 7:00 and 9:00, and on the pre-2018 period.

See `project_question/deliverable.md` for the full proposal.
