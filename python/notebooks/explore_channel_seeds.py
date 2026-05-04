import marimo

__generated_with = "0.23.4"
app = marimo.App(width="medium")


@app.cell
def _():
    import marimo as mo

    return (mo,)


@app.cell
def _(mo):
    mo.md("""
    # Channel-seed exploration

    Distribution of channels surfaced by `code/00b_discover_candidates.R`.

    - `data/channels_candidates_full.csv` — every candidate (in-band and
      out-of-band) with subscriber count, creation date, country.
    - `data/channels_seeds.csv` — the in-band subset, ready to feed
      `00_resolve_channels.R`.

    Use this notebook before running the resolver, to sanity-check
    category coverage, the subscriber-count distribution, and how many
    channels predate the 2020-07-27 policy switch.
    """)
    return


@app.cell
def _():
    from pathlib import Path

    import altair as alt
    import pandas as pd

    PROJECT_ROOT = Path(__file__).resolve().parents[1]
    POLICY_DATE = pd.Timestamp("2020-07-27")
    return POLICY_DATE, PROJECT_ROOT, alt, pd


@app.cell
def _(PROJECT_ROOT, mo, pd):
    candidates_path = PROJECT_ROOT / "data" / "channels_candidates_full.csv"
    seeds_path = PROJECT_ROOT / "data" / "channels_seeds.csv"

    if not candidates_path.exists():
        mo.stop(
            True,
            mo.md(
                f"`{candidates_path.relative_to(PROJECT_ROOT)}` not found. "
                "Run `Rscript code/00b_discover_candidates.R` first."
            ),
        )

    candidates = pd.read_csv(candidates_path, parse_dates=["channel_created"])
    seeds = (
        pd.read_csv(seeds_path)
        if seeds_path.exists()
        else pd.DataFrame(columns=["handle_or_url", "primary_category"])
    )
    return candidates, seeds


@app.cell
def _(candidates, mo, seeds):
    mo.md(f"""
    **Loaded:**
    - {len(candidates):,} total candidates
    - {int(candidates['in_band'].sum()):,} in 10K–1M sub band
    - {len(seeds):,} rows in `channels_seeds.csv`
    """)
    return


@app.cell
def _(mo):
    mo.md("""
    ## In-band candidates by category
    """)
    return


@app.cell
def _(alt, candidates):
    cat_counts = (
        candidates.query("in_band")
        .groupby("primary_category")
        .size()
        .reset_index(name="n")
        .sort_values("n", ascending=False)
    )

    chart_cat = (
        alt.Chart(cat_counts)
        .mark_bar()
        .encode(
            x=alt.X("n:Q", title="In-band channels"),
            y=alt.Y("primary_category:N", sort="-x", title=None),
            tooltip=["primary_category", "n"],
        )
        .properties(height=180)
    )
    chart_cat
    return


@app.cell
def _(mo):
    mo.md("""
    ## Subscriber-count distribution

    Log-scaled. Vertical guides at 10K and 1M mark the band edges.
    """)
    return


@app.cell
def _(alt, candidates, pd):
    import numpy as np

    sub_df = candidates.dropna(subset=["subscriber_count"]).copy()
    sub_df = sub_df[sub_df["subscriber_count"] > 0].copy()

    # Half-decade log-spaced edges from 100 to 100M.
    edges = np.logspace(2, 8, 13)

    def _fmt(x):
        if x >= 1e6:
            return f"{x / 1e6:g}M"
        if x >= 1e3:
            return f"{x / 1e3:g}K"
        return f"{x:.0f}"

    labels = [f"{_fmt(edges[i])}–{_fmt(edges[i + 1])}"
              for i in range(len(edges) - 1)]
    sub_df["bucket"] = pd.cut(
        sub_df["subscriber_count"],
        bins=edges,
        labels=labels,
        include_lowest=True,
    )

    counts = (
        sub_df.groupby(["bucket", "in_band"], observed=True)
        .size()
        .reset_index(name="n")
    )

    hist = (
        alt.Chart(counts)
        .mark_bar()
        .encode(
            x=alt.X("bucket:N", sort=labels,
                    title="Subscribers (log-spaced bins)"),
            y=alt.Y("n:Q", title="Channels"),
            color=alt.Color(
                "in_band:N",
                title="In 10K–1M band",
                scale=alt.Scale(domain=[True, False],
                                range=["#2b8cbe", "#bdbdbd"]),
            ),
            tooltip=["bucket:N", "in_band:N", "n:Q"],
        )
        .properties(height=240)
    )
    hist
    return


@app.cell
def _(mo):
    mo.md("""
    ## Window coverage

    How many in-band channels span enough of the 2018–2023 study window
    to contribute to each density test?

    - **full (pre-2019 channel):** has both pre- and post-policy uploads
    - **partial pre-policy:** created 2019-01 to 2020-07, thin pre-policy coverage
    - **post-policy only:** created after 2020-07-27, only contributes to the
      480s cutoff test
    """)
    return


@app.cell
def _(alt, candidates):
    coverage_order = [
        "full (pre-2019 channel)",
        "partial pre-policy",
        "post-policy only",
        "unknown",
    ]
    cov = (
        candidates.query("in_band")
        .groupby(["primary_category", "window_coverage"])
        .size()
        .reset_index(name="n")
    )
    chart_cov = (
        alt.Chart(cov)
        .mark_bar()
        .encode(
            x=alt.X("n:Q", stack="normalize",
                    title="Share of in-band channels"),
            y=alt.Y("primary_category:N", title=None, sort="-x"),
            color=alt.Color(
                "window_coverage:N",
                sort=coverage_order,
                scale=alt.Scale(
                    domain=coverage_order,
                    range=["#1a9850", "#fdae61", "#d73027", "#999999"],
                ),
            ),
            tooltip=["primary_category", "window_coverage", "n"],
        )
        .properties(height=180)
    )
    chart_cov
    return


@app.cell
def _(mo):
    mo.md("""
    ## Channel-creation date
    """)
    return


@app.cell
def _(POLICY_DATE, alt, candidates, pd):
    age = candidates.query("in_band").dropna(subset=["channel_created"])
    age = age.assign(
        year_created=pd.to_datetime(age["channel_created"]).dt.year
    )
    chart_age = (
        alt.Chart(age)
        .mark_bar()
        .encode(
            x=alt.X("year_created:O", title="Channel creation year"),
            y=alt.Y("count():Q", title="Channels"),
            color=alt.Color("primary_category:N", title="Category"),
            tooltip=["primary_category", "year_created", "count():Q"],
        )
        .properties(height=240)
    )
    rule = (
        alt.Chart(pd.DataFrame({"y": [POLICY_DATE.year]}))
        .mark_rule(color="firebrick", strokeDash=[4, 3])
        .encode(x="y:O")
    )
    chart_age + rule
    return


@app.cell
def _(mo):
    mo.md("""
    ## Browse the in-band candidates

    Sortable / filterable. Use this to spot off-topic channels you
    want to drop, or to find good manual additions before running the
    resolver.
    """)
    return


@app.cell
def _(candidates, mo):
    cols = [
        "channel_title",
        "primary_category",
        "subscriber_count",
        "video_count",
        "channel_created",
        "window_coverage",
        "country",
        "custom_url",
        "channel_id",
    ]
    available = [c for c in cols if c in candidates.columns]
    table = mo.ui.table(
        candidates.query("in_band")[available]
        .sort_values(["primary_category", "subscriber_count"],
                     ascending=[True, False])
        .reset_index(drop=True),
        page_size=25,
    )
    table
    return


@app.cell
def _(mo):
    mo.md("""
    ---

    **Next step:** edit `data/channels_seeds.csv` (drop off-topic
    rows, add personal favorites as `@handle, primary_category`),
    then run `Rscript code/00_resolve_channels.R`.
    """)
    return


if __name__ == "__main__":
    app.run()
