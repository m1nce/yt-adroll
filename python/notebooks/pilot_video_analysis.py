import marimo

__generated_with = "0.23.3"
app = marimo.App(width="medium")


@app.cell
def _():
    import marimo as mo

    return (mo,)


@app.cell
def _(mo):
    mo.md("""
    # Pilot video analysis

    Interactive exploration of `data/pilot_videos.parquet`. The R script
    `code/03_explore_pilot.R` produces the canonical Section-1 stats and
    the embedded-in-PDF figures; this notebook is the *exploration*
    artifact — cross-filters, channel deep-dives, what-if cutoff bands,
    and views the writeup can't easily render.

    Use the controls below to slice the sample. Filters propagate to most
    sections; sections that need the full sample (per-channel pre/post
    shift, time trend) ignore the filters and say so inline.
    """)
    return


@app.cell
def _():
    import math
    from pathlib import Path

    import altair as alt
    import numpy as np
    import pandas as pd

    PROJECT_ROOT = Path(__file__).resolve().parents[2]
    POLICY_DATE = pd.Timestamp("2020-07-27", tz="UTC")
    CUTOFF_PRE = 600  # 10:00, applies before POLICY_DATE
    CUTOFF_POST = 480  # 8:00, applies on/after POLICY_DATE
    SHORTS_MAX = 61  # YouTube Shorts ceiling (60s) + 1s for API rounding leakage
    return (
        CUTOFF_POST,
        CUTOFF_PRE,
        POLICY_DATE,
        PROJECT_ROOT,
        SHORTS_MAX,
        alt,
        math,
        np,
        pd,
    )


@app.cell
def _(PROJECT_ROOT, mo, pd):
    _videos_path = PROJECT_ROOT / "data" / "pilot_videos.parquet"
    _channels_path = PROJECT_ROOT / "data" / "channels.parquet"

    if not _videos_path.exists():
        mo.stop(
            True,
            mo.md(
                f"`{_videos_path.relative_to(PROJECT_ROOT)}` not found. "
                "Run `Rscript code/02_pull_videos.R` first."
            ),
        )

    videos_raw = pd.read_parquet(_videos_path)
    channels = pd.read_parquet(_channels_path)

    videos_raw["published_at"] = pd.to_datetime(
        videos_raw["published_at"], utc=True
    )
    return channels, videos_raw


@app.cell
def _(channels, mo, videos_raw):
    mo.md(f"""
    **Loaded:**
    - {len(videos_raw):,} videos in the study window (2018-01 – 2023-12)
    - {videos_raw['channel_id'].nunique():,} unique channels with in-window uploads
    - {len(channels):,} channels in the frame total
    """)
    return


@app.cell
def _(mo):
    shorts_toggle = mo.ui.switch(
        value=True,
        label="Exclude YouTube Shorts (≤61s, with rounding leakage)",
    )
    shorts_toggle
    return (shorts_toggle,)


@app.cell
def _(POLICY_DATE, SHORTS_MAX, channels, np, shorts_toggle, videos_raw):
    if shorts_toggle.value:
        _v = videos_raw[videos_raw["duration_sec"] > SHORTS_MAX].copy()
    else:
        _v = videos_raw.copy()

    _chan_meta_cols = [
        c for c in
        ["channel_id", "channel_created", "window_coverage", "custom_url"]
        if c in channels.columns
    ]
    _v = _v.merge(channels[_chan_meta_cols], on="channel_id", how="left")
    _v["period"] = np.where(
        _v["published_at"] < POLICY_DATE, "pre-policy", "post-policy"
    )
    videos = _v
    return (videos,)


@app.cell
def _(mo, videos):
    mo.md(f"""
    After Shorts filter (if applied): **{len(videos):,} videos**, **{videos['channel_id'].nunique():,} channels**.
    """)
    return


@app.cell
def _(mo, videos):
    _channel_options = sorted(videos["channel_title"].dropna().unique().tolist())
    _category_options = sorted(videos["primary_category"].dropna().unique().tolist())

    channel_select = mo.ui.multiselect(
        options=_channel_options,
        value=_channel_options,
        label="Channels (default: all)",
    )
    category_select = mo.ui.multiselect(
        options=_category_options,
        value=_category_options,
        label="Categories (default: all)",
    )
    period_radio = mo.ui.radio(
        options=["all", "pre-policy", "post-policy"],
        value="all",
        label="Period",
    )
    bandwidth_slider = mo.ui.slider(
        start=15, stop=120, step=5, value=30,
        label="Cutoff bandwidth (seconds, used in §3, §5, §9)",
        show_value=True,
    )

    mo.vstack([
        category_select,
        period_radio,
        bandwidth_slider,
        channel_select,
    ])
    return bandwidth_slider, category_select, channel_select, period_radio


@app.cell
def _(category_select, channel_select, videos):
    # Period-agnostic filtered frame: respects channel + category but NOT
    # the period radio. Used by sections that need pre/post overlays
    # (Section 2 KDE/ECDF), period-specific zooms (Section 3), and the
    # per-channel deep dive (Section 6).
    df_no_period = videos[
        videos["channel_title"].isin(channel_select.value) &
        videos["primary_category"].isin(category_select.value)
    ].copy()
    return (df_no_period,)


@app.cell
def _(df_no_period, period_radio):
    _df = df_no_period
    if period_radio.value != "all":
        _df = _df[_df["period"] == period_radio.value]
    df = _df.copy()
    return (df,)


@app.cell
def _(df, mo):
    if len(df) == 0:
        mo.stop(True, mo.md("**No videos match the current filters.**"))
    mo.md(
        f"Filtered sample: **{len(df):,} videos**, "
        f"**{df['channel_id'].nunique():,} channels**."
    )
    return


@app.cell
def _(mo):
    mo.md("""
    ## Section 1 — Sample composition
    """)
    return


@app.cell
def _(alt, df):
    _cat_chan = (
        df.groupby(["primary_category", "channel_title"])
        .size().reset_index(name="n")
    )
    _chart = (
        alt.Chart(_cat_chan)
        .mark_rect()
        .encode(
            x=alt.X("primary_category:N", title="Category"),
            y=alt.Y("channel_title:N", title=None,
                    sort=alt.SortField("n", order="descending")),
            color=alt.Color("n:Q", title="Videos",
                            scale=alt.Scale(scheme="blues")),
            tooltip=["channel_title", "primary_category", "n"],
        )
        .properties(height=400, title="Channel × category, video counts")
    )
    _chart
    return


@app.cell
def _(alt, df):
    _cov = (
        df.dropna(subset=["window_coverage"])
        .groupby(["primary_category", "window_coverage"])
        .size().reset_index(name="n")
    )
    _coverage_order = [
        "full (pre-2019 channel)",
        "partial pre-policy",
        "post-policy only",
        "unknown",
    ]
    _chart = (
        alt.Chart(_cov)
        .mark_bar()
        .encode(
            x=alt.X("n:Q", title="Videos in pilot"),
            y=alt.Y("primary_category:N", title=None, sort="-x"),
            color=alt.Color(
                "window_coverage:N",
                sort=_coverage_order,
                scale=alt.Scale(
                    domain=_coverage_order,
                    range=["#1a9850", "#fdae61", "#d73027", "#999999"],
                ),
            ),
            tooltip=["primary_category", "window_coverage", "n"],
        )
        .properties(height=180, title="Window coverage by category (videos)")
    )
    _chart
    return


@app.cell
def _(df, mo, pd):
    _per_channel = (
        df.groupby(["channel_id", "channel_title", "primary_category"])
        .agg(
            n_videos=("video_id", "count"),
            n_pre=("period", lambda s: (s == "pre-policy").sum()),
            n_post=("period", lambda s: (s == "post-policy").sum()),
            first_upload=("published_at", "min"),
            last_upload=("published_at", "max"),
            median_duration=("duration_sec", "median"),
        )
        .reset_index()
        .sort_values("n_videos", ascending=False)
    )
    _per_channel["first_upload"] = pd.to_datetime(_per_channel["first_upload"]).dt.date
    _per_channel["last_upload"] = pd.to_datetime(_per_channel["last_upload"]).dt.date
    mo.ui.table(_per_channel, page_size=20)
    return


@app.cell
def _(mo):
    mo.md("""
    ## Section 2 — Duration distribution
    """)
    return


@app.cell
def _(CUTOFF_POST, CUTOFF_PRE, alt, df, pd):
    _in_range = df[(df["duration_sec"] >= 60) & (df["duration_sec"] <= 1200)]
    _cutoffs = pd.DataFrame({"x": [CUTOFF_POST, CUTOFF_PRE],
                             "label": ["8:00 (post)", "10:00 (pre)"]})
    _hist = (
        alt.Chart(_in_range)
        .mark_bar()
        .encode(
            x=alt.X("duration_sec:Q",
                    bin=alt.Bin(step=1),
                    title="Duration (seconds)"),
            y=alt.Y("count():Q", title="Videos"),
            color=alt.Color(
                "period:N",
                scale=alt.Scale(
                    domain=["pre-policy", "post-policy"],
                    range=["#984ea3", "#377eb8"]),
            ),
            tooltip=["count():Q"],
        )
        .properties(height=240, title="Duration histogram, 60–1200s, 1s bins")
    )
    _rules = (
        alt.Chart(_cutoffs)
        .mark_rule(color="firebrick", strokeDash=[4, 3])
        .encode(x="x:Q", tooltip=["label:N"])
    )
    _hist + _rules
    return


@app.cell
def _(CUTOFF_POST, CUTOFF_PRE, alt, df_no_period, pd):
    # Uses df_no_period so the pre/post overlay is visible regardless of
    # the period radio.
    _in_range = df_no_period[
        (df_no_period["duration_sec"] >= 62) &
        (df_no_period["duration_sec"] <= 1200)
    ]
    _kde = (
        alt.Chart(_in_range)
        .transform_density(
            "duration_sec",
            groupby=["period"],
            extent=[62, 1200],
            steps=400,
        )
        .mark_line()
        .encode(
            x=alt.X("value:Q", title="Duration (seconds)"),
            y=alt.Y("density:Q", title="KDE density"),
            color=alt.Color(
                "period:N",
                scale=alt.Scale(
                    domain=["pre-policy", "post-policy"],
                    range=["#984ea3", "#377eb8"]),
            ),
        )
    )
    _rules = (
        alt.Chart(pd.DataFrame({"x": [CUTOFF_POST, CUTOFF_PRE]}))
        .mark_rule(color="firebrick", strokeDash=[4, 3])
        .encode(x="x:Q")
    )
    (_kde + _rules).properties(height=240,
                                title="KDE — pre vs post (overlaid)")
    return


@app.cell
def _(CUTOFF_POST, CUTOFF_PRE, alt, df_no_period, pd):
    # Uses df_no_period for the same pre/post overlay reason as the KDE.
    _in_range = df_no_period[
        (df_no_period["duration_sec"] >= 62) &
        (df_no_period["duration_sec"] <= 1200)
    ]
    _ecdf = (
        alt.Chart(_in_range)
        .transform_window(
            cumulative_count="count()",
            sort=[{"field": "duration_sec"}],
            groupby=["period"],
        )
        .transform_joinaggregate(
            total="count()",
            groupby=["period"],
        )
        .transform_calculate(
            ecdf="datum.cumulative_count / datum.total"
        )
        .mark_line()
        .encode(
            x=alt.X("duration_sec:Q", title="Duration (seconds)"),
            y=alt.Y("ecdf:Q", title="ECDF"),
            color=alt.Color(
                "period:N",
                scale=alt.Scale(
                    domain=["pre-policy", "post-policy"],
                    range=["#984ea3", "#377eb8"]),
            ),
        )
    )
    _rules = (
        alt.Chart(pd.DataFrame({"x": [CUTOFF_POST, CUTOFF_PRE]}))
        .mark_rule(color="firebrick", strokeDash=[4, 3])
        .encode(x="x:Q")
    )
    (_ecdf + _rules).properties(height=240, title="ECDF — pre vs post")
    return


@app.cell
def _(mo):
    mo.md("""
    ## Section 3 — Bunching preview at the cutoffs
    """)
    return


@app.cell
def _(CUTOFF_POST, alt, df_no_period):
    # Pulls from df_no_period so the period radio doesn't blank this out.
    _post_zoom = df_no_period[
        (df_no_period["period"] == "post-policy") &
        (df_no_period["duration_sec"] >= 420) &
        (df_no_period["duration_sec"] <= 540)
    ]
    _chart = (
        alt.Chart(_post_zoom)
        .mark_bar()
        .encode(
            x=alt.X("duration_sec:Q",
                    bin=alt.Bin(step=1),
                    title="Duration (seconds)"),
            y=alt.Y("count():Q", title="Videos"),
            tooltip=["count():Q"],
        )
        .properties(height=200, title="Post-policy zoom: 7:00–9:00")
    )
    _rule = alt.Chart().mark_rule(color="firebrick").encode(
        x=alt.datum(CUTOFF_POST)
    )
    _chart + _rule
    return


@app.cell
def _(CUTOFF_PRE, alt, df_no_period):
    # Same period-agnostic source as the post-policy zoom above.
    _pre_zoom = df_no_period[
        (df_no_period["period"] == "pre-policy") &
        (df_no_period["duration_sec"] >= 540) &
        (df_no_period["duration_sec"] <= 660)
    ]
    _chart = (
        alt.Chart(_pre_zoom)
        .mark_bar()
        .encode(
            x=alt.X("duration_sec:Q",
                    bin=alt.Bin(step=1),
                    title="Duration (seconds)"),
            y=alt.Y("count():Q", title="Videos"),
            tooltip=["count():Q"],
        )
        .properties(height=200, title="Pre-policy zoom: 9:00–11:00")
    )
    _rule = alt.Chart().mark_rule(color="firebrick").encode(
        x=alt.datum(CUTOFF_PRE)
    )
    _chart + _rule
    return


@app.cell
def _(alt, bandwidth_slider, df, pd):
    _bw = bandwidth_slider.value
    _cutoffs = [
        (420, "7:00 (placebo)", "post-policy"),
        (480, "8:00 (active)", "post-policy"),
        (540, "9:00 (placebo)", "post-policy"),
        (540, "9:00 (placebo)", "pre-policy"),
        (600, "10:00 (active)", "pre-policy"),
        (660, "11:00 (placebo)", "pre-policy"),
    ]
    _rows = []
    for _c, _label, _period in _cutoffs:
        _sub = df[df["period"] == _period]
        _below = (
            (_sub["duration_sec"] >= _c - _bw) & (_sub["duration_sec"] < _c)
        ).sum()
        _above = (
            (_sub["duration_sec"] >= _c) & (_sub["duration_sec"] < _c + _bw)
        ).sum()
        _ratio = (_above / _below) if _below > 0 else float("nan")
        _rows.append({
            "cutoff": _c, "label": _label, "period": _period,
            "n_below": int(_below), "n_above": int(_above),
            "mass_ratio": _ratio,
        })
    _mass_df = pd.DataFrame(_rows)

    _chart = (
        alt.Chart(_mass_df)
        .mark_bar()
        .encode(
            x=alt.X("label:N", title="Cutoff", sort=None),
            y=alt.Y("mass_ratio:Q",
                    title=f"Mass ratio (above ±{_bw}s / below ±{_bw}s)"),
            color=alt.Color(
                "period:N",
                scale=alt.Scale(
                    domain=["pre-policy", "post-policy"],
                    range=["#984ea3", "#377eb8"]),
            ),
            tooltip=["label", "period", "n_below", "n_above", "mass_ratio"],
        )
        .properties(height=220,
                    title="Mass ratios — actual vs placebo cutoffs")
    )
    _line1 = alt.Chart(pd.DataFrame({"y": [1.0]})).mark_rule(
        color="grey", strokeDash=[4, 3]
    ).encode(y="y:Q")
    _chart + _line1
    return


@app.cell
def _(mo):
    mo.md("""
    ## Section 4 — Per-category & Sports placebo
    """)
    return


@app.cell
def _(alt, df):
    _in_range = df[(df["duration_sec"] >= 60) & (df["duration_sec"] <= 1200)]
    _facet = (
        alt.Chart(_in_range)
        .mark_bar()
        .encode(
            x=alt.X("duration_sec:Q", bin=alt.Bin(step=5),
                    title="Duration (seconds, 5s bins)"),
            y=alt.Y("count():Q", title="Videos"),
            color=alt.Color(
                "period:N",
                scale=alt.Scale(
                    domain=["pre-policy", "post-policy"],
                    range=["#984ea3", "#377eb8"]),
            ),
        )
        .properties(width=320, height=120)
        .facet(facet="primary_category:N", columns=2)
    )
    _facet
    return


@app.cell
def _(alt, bandwidth_slider, df, pd):
    _bw = bandwidth_slider.value
    _rows = []
    for _cat in df["primary_category"].dropna().unique():
        for _c, _period_filter in [(480, "post-policy"), (600, "pre-policy")]:
            _sub = df[
                (df["primary_category"] == _cat) &
                (df["period"] == _period_filter)
            ]
            if len(_sub) == 0:
                continue
            _below = (
                (_sub["duration_sec"] >= _c - _bw) &
                (_sub["duration_sec"] < _c)
            ).sum()
            _above = (
                (_sub["duration_sec"] >= _c) &
                (_sub["duration_sec"] < _c + _bw)
            ).sum()
            _rows.append({
                "category": _cat,
                "cutoff": f"{_c}s ({_period_filter})",
                "is_sports": _cat == "Sports",
                "ratio": (_above / _below) if _below > 0 else float("nan"),
                "n_below": int(_below), "n_above": int(_above),
            })
    _cat_mass = pd.DataFrame(_rows)

    _bars = (
        alt.Chart(_cat_mass)
        .mark_bar()
        .encode(
            x=alt.X("category:N", title=None, sort="-y"),
            y=alt.Y("ratio:Q", title="Mass ratio (above / below)"),
            color=alt.Color(
                "is_sports:N",
                title="Placebo (Sports)?",
                scale=alt.Scale(domain=[True, False],
                                range=["#d62728", "#1f77b4"]),
            ),
            tooltip=["category", "cutoff", "n_below", "n_above", "ratio"],
        )
    )
    # Same data source as _bars so the layer can be faceted; alt.datum(1.0)
    # renders a constant horizontal reference line in every facet panel.
    _line1 = (
        alt.Chart(_cat_mass)
        .mark_rule(color="grey", strokeDash=[4, 3])
        .encode(y=alt.datum(1.0))
    )
    (_bars + _line1).properties(width=240, height=200).facet(facet="cutoff:N")
    return


@app.cell
def _(mo):
    mo.md("""
    ## Section 5 — Engagement near the cutoffs
    """)
    return


@app.cell
def _(alt, bandwidth_slider, df, math, mo, pd):
    _bw = bandwidth_slider.value
    _sub = df[
        (df["period"] == "post-policy") &
        (df["duration_sec"] >= 480 - _bw) &
        (df["duration_sec"] < 480 + _bw)
    ].copy()

    if len(_sub) == 0:
        _output = mo.md("(No videos in the current filter near 8:00.)")
    else:
        _sub["side"] = _sub["duration_sec"].apply(
            lambda d: "below 8:00" if d < 480 else "at/above 8:00"
        )
        _long = []
        for _metric in ["view_count", "like_count", "comment_count"]:
            _d = _sub[["side", _metric]].dropna().rename(
                columns={_metric: "value"}
            )
            _d["metric"] = _metric
            _long.append(_d)
        _eng = pd.concat(_long, ignore_index=True)
        _eng = _eng[_eng["value"] > 0].copy()

        if len(_eng) == 0:
            _output = mo.md(
                "(All engagement values are zero or missing in this window.)"
            )
        else:
            _eng["log_value"] = _eng["value"].apply(math.log10)
            _output = (
                alt.Chart(_eng)
                .mark_boxplot()
                .encode(
                    x=alt.X("side:N", title=None,
                            sort=["below 8:00", "at/above 8:00"]),
                    y=alt.Y("log_value:Q", title="log10(value)"),
                    color=alt.Color(
                        "side:N",
                        scale=alt.Scale(
                            domain=["below 8:00", "at/above 8:00"],
                            range=["#999999", "#1f77b4"]),
                    ),
                )
                .properties(width=200, height=200)
                .facet(facet="metric:N")
            )
    _output
    return


@app.cell
def _(bandwidth_slider, df, mo):
    _bw = bandwidth_slider.value
    _sub = df[
        (df["period"] == "post-policy") &
        (df["duration_sec"] >= 480 - _bw) &
        (df["duration_sec"] < 480 + _bw)
    ].copy()
    if len(_sub) == 0:
        _output = mo.md("(No videos in the current filter near 8:00.)")
    else:
        _sub["side"] = _sub["duration_sec"].apply(
            lambda d: "below 8:00" if d < 480 else "at/above 8:00"
        )
        _summary = _sub.groupby("side").agg(
            n=("video_id", "count"),
            median_views=("view_count", "median"),
            median_likes=("like_count", "median"),
            median_comments=("comment_count", "median"),
        ).reset_index()
        _output = mo.ui.table(_summary, page_size=10)
    _output
    return


@app.cell
def _(alt, df, math):
    _sub = df.dropna(subset=["view_count", "duration_sec"]).copy()
    _sub = _sub[
        (_sub["duration_sec"] >= 62) &
        (_sub["duration_sec"] <= 1200) &
        (_sub["view_count"] > 0)
    ]
    _sub["log_views"] = _sub["view_count"].apply(math.log10)

    _chart = (
        alt.Chart(_sub)
        .mark_circle(opacity=0.4)
        .encode(
            x=alt.X("duration_sec:Q", title="Duration (seconds)"),
            y=alt.Y("log_views:Q", title="log10(view_count)"),
            color=alt.Color(
                "period:N",
                scale=alt.Scale(
                    domain=["pre-policy", "post-policy"],
                    range=["#984ea3", "#377eb8"]),
            ),
            tooltip=["channel_title:N", "duration_sec:Q",
                     "view_count:Q", "title:N"],
        )
        .properties(height=300, title="Duration vs log(view_count)")
    )
    _rule = alt.Chart().mark_rule(color="firebrick").encode(
        x=alt.datum(480)
    )
    _chart + _rule
    return


@app.cell
def _(mo):
    mo.md("""
    ## Section 6 — Per-channel deep dive
    """)
    return


@app.cell
def _(df_no_period, mo):
    # Options from df_no_period so the picker is stable across period changes.
    _opts = sorted(df_no_period["channel_title"].dropna().unique().tolist())
    if not _opts:
        mo.stop(True, mo.md("No channels in current filter."))
    channel_picker = mo.ui.dropdown(
        options=_opts,
        value=_opts[0],
        label="Pick a channel",
    )
    channel_picker
    return (channel_picker,)


@app.cell
def _(CUTOFF_POST, CUTOFF_PRE, alt, channel_picker, df_no_period, pd):
    # Per-channel deep dive — period radio is intentionally ignored so the
    # full timeline is visible.
    _sel = df_no_period[df_no_period["channel_title"] == channel_picker.value]
    _sel_in = _sel[
        (_sel["duration_sec"] >= 62) &
        (_sel["duration_sec"] <= 1200)
    ]
    _hist = (
        alt.Chart(_sel_in)
        .mark_bar()
        .encode(
            x=alt.X("duration_sec:Q", bin=alt.Bin(step=5),
                    title="Duration (seconds)"),
            y=alt.Y("count():Q", title="Videos"),
            color=alt.Color(
                "period:N",
                scale=alt.Scale(
                    domain=["pre-policy", "post-policy"],
                    range=["#984ea3", "#377eb8"]),
            ),
        )
        .properties(width=600, height=180,
                    title=f"{channel_picker.value} — duration distribution")
    )
    _rules = (
        alt.Chart(pd.DataFrame({"x": [CUTOFF_POST, CUTOFF_PRE]}))
        .mark_rule(color="firebrick", strokeDash=[4, 3])
        .encode(x="x:Q")
    )
    _hist + _rules
    return


@app.cell
def _(POLICY_DATE, alt, channel_picker, df_no_period, mo, pd):
    _sel = df_no_period[
        df_no_period["channel_title"] == channel_picker.value
    ].copy()
    if len(_sel) == 0:
        _output = mo.md("(No videos for that channel under current filters.)")
    else:
        _timeline = (
            alt.Chart(_sel)
            .mark_circle(opacity=0.6)
            .encode(
                x=alt.X("published_at:T", title="Upload date"),
                y=alt.Y("duration_sec:Q",
                        title="Duration (seconds)",
                        scale=alt.Scale(type="log",
                                        domain=[60, 7200])),
                color=alt.Color(
                    "period:N",
                    scale=alt.Scale(
                        domain=["pre-policy", "post-policy"],
                        range=["#984ea3", "#377eb8"]),
                ),
                tooltip=["title:N", "duration_sec:Q",
                         "published_at:T", "view_count:Q"],
            )
            .properties(width=600, height=240,
                        title=f"{channel_picker.value} — uploads over time")
        )
        _policy_rule = (
            alt.Chart(pd.DataFrame({"x": [POLICY_DATE]}))
            .mark_rule(color="firebrick", strokeDash=[4, 3])
            .encode(x="x:T")
        )
        _output = _timeline + _policy_rule
    _output
    return


@app.cell
def _(mo):
    mo.md("""
    ## Section 7 — Duration trend over time

    *Ignores the channel/category filters above to keep the time-series
    panel readable; respects the Shorts toggle.*
    """)
    return


@app.cell
def _(POLICY_DATE, alt, pd, videos):
    _monthly = (
        videos.assign(
            month=videos["published_at"].dt.tz_convert("UTC")
            .dt.to_period("M").dt.to_timestamp()
        )
        .groupby(["month", "primary_category"])["duration_sec"]
        .agg(median="median", p75=lambda x: x.quantile(0.75))
        .reset_index()
    )

    _base = alt.Chart(_monthly).encode(x=alt.X("month:T", title="Upload month"))
    _median_line = _base.mark_line().encode(
        y=alt.Y("median:Q", title="Median duration (seconds)"),
        color=alt.Color("primary_category:N", title="Category"),
    )
    _p75_line = _base.mark_line(strokeDash=[2, 2], opacity=0.6).encode(
        y=alt.Y("p75:Q"),
        color=alt.Color("primary_category:N"),
    )
    _policy_rule = (
        alt.Chart(pd.DataFrame({"x": [POLICY_DATE]}))
        .mark_rule(color="firebrick", strokeDash=[4, 3])
        .encode(x="x:T")
    )
    (_median_line + _p75_line + _policy_rule).properties(
        height=300,
        title="Monthly median (solid) & p75 (dashed) duration, by category",
    ).resolve_scale(y="shared")
    return


@app.cell
def _(mo):
    mo.md("""
    ## Section 8 — Per-channel pre-vs-post shift

    *Ignores the channel filter; only includes channels with ≥10 pre-policy
    AND ≥10 post-policy videos in the current category/Shorts selection.
    Pilot has very few full-coverage channels; this section's real value is
    on the full pull.*
    """)
    return


@app.cell
def _(alt, category_select, mo, pd, videos):
    _sub = videos[videos["primary_category"].isin(category_select.value)].copy()
    _counts = _sub.groupby(["channel_title", "period"]).size().unstack(fill_value=0)
    _qualifying = _counts[
        (_counts.get("pre-policy", 0) >= 10) &
        (_counts.get("post-policy", 0) >= 10)
    ].index

    if len(_qualifying) == 0:
        _output = mo.md(
            "**No channels in the current category selection have ≥10 "
            "videos on each side of the policy date.** Expected for the "
            "pilot — full pull will populate this."
        )
    else:
        _paired = (
            _sub[_sub["channel_title"].isin(_qualifying)]
            .groupby(["channel_title", "primary_category", "period"])
            ["duration_sec"].median()
            .reset_index()
        )
        _slope = (
            alt.Chart(_paired)
            .mark_line(point=True)
            .encode(
                x=alt.X("period:N",
                        sort=["pre-policy", "post-policy"],
                        title=None),
                y=alt.Y("duration_sec:Q",
                        title="Median duration (seconds)"),
                color=alt.Color("primary_category:N", title="Category"),
                detail="channel_title:N",
                tooltip=["channel_title:N", "period:N", "duration_sec:Q"],
            )
            .properties(
                height=320,
                title=("Within-channel median duration shift "
                       f"({len(_qualifying)} qualifying channels)"),
            )
        )
        _cutoff_rules = pd.DataFrame({"y": [480, 600],
                                       "label": ["8:00 (post)", "10:00 (pre)"]})
        _rules = (
            alt.Chart(_cutoff_rules)
            .mark_rule(color="firebrick", strokeDash=[4, 3])
            .encode(y="y:Q", tooltip=["label:N"])
        )
        _output = _slope + _rules
    _output
    return


@app.cell
def _(mo):
    mo.md("""
    ## Section 9 — Title spot-check at the cutoffs

    Videos in tight windows around 8:00 (post) and 10:00 (pre). Sortable —
    eyeball the titles for signs of padding (long intros, "thanks for
    watching", etc.). Respects the channel/category filters.
    """)
    return


@app.cell
def _(bandwidth_slider, df, mo, pd):
    _bw = bandwidth_slider.value
    _near_post = df[
        (df["period"] == "post-policy") &
        (df["duration_sec"] >= 480 - _bw) &
        (df["duration_sec"] < 480 + _bw)
    ].copy()
    _near_pre = df[
        (df["period"] == "pre-policy") &
        (df["duration_sec"] >= 600 - _bw) &
        (df["duration_sec"] < 600 + _bw)
    ].copy()

    _cols = ["channel_title", "primary_category", "duration_sec",
             "view_count", "like_count", "title", "published_at"]

    if len(_near_post) == 0 and len(_near_pre) == 0:
        _output = mo.md("(No videos within the bandwidth around either cutoff.)")
    else:
        _near_post = _near_post[_cols].assign(window=f"8:00 ±{_bw}s (post)")
        _near_pre = _near_pre[_cols].assign(window=f"10:00 ±{_bw}s (pre)")
        _combined = (
            pd.concat([_near_post, _near_pre], ignore_index=True)
            .sort_values(["window", "duration_sec"])
            .reset_index(drop=True)
        )
        _output = mo.ui.table(_combined, page_size=25)
    _output
    return


@app.cell
def _(mo):
    mo.md("""
    ---

    End of pilot exploration. The canonical PoA Section-1 inputs come
    from `code/03_explore_pilot.R`; this notebook is the interactive
    exploration artifact.
    """)
    return


if __name__ == "__main__":
    app.run()
