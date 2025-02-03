use crate::load::SiteCtxt;

use collector::{Bound, MasterCommit};
use database::selector::StatisticSeries;
use database::selector::{BenchmarkQuery, SeriesResponse};
use database::ArtifactId;
use database::{Commit, Index};

use std::ops::RangeInclusive;
use std::sync::Arc;
use std::time::Instant;

/// Finds the most appropriate `ArtifactId` for a given bound.
///
/// Searches the commits in the index either from the left or the right.
/// If not found in those commits, searches through the artifacts in the index.
pub async fn artifact_id_for_bound(
    ctxt: &SiteCtxt,
    master_commits: &[MasterCommit],
    data: &Index,
    bound: Bound,
    is_left: bool,
) -> Option<ArtifactId> {
    let commits = data.commits();
    let mut commit = if is_left {
        commits
            .iter()
            .find(|commit| bound.left_match(master_commits, commit))
            .cloned()
    } else {
        commits
            .iter()
            .rfind(|commit| bound.right_match(master_commits, commit))
            .cloned()
    };
    if is_left && commit.is_none() {
        if bound == Bound::None {
            commit = commits
                .iter()
                .rev()
                .filter_map(|commit| bound.right_match(master_commits, commit).then(|| commit))
                .nth(1)
                .cloned();
        }
    }
    if commit.is_none() {
        if let Bound::Commit(c) = &bound {
            let pr_commit = ctxt
                .conn()
                .await
                .pr_sha_of(c.as_str())
                .await
                .map(Bound::Commit);
            if let Some(pr_bound) = pr_commit {
                commit = commits
                    .iter()
                    .rfind(|commit| pr_bound.right_match(master_commits, commit))
                    .cloned()
            }
        }
    }
    if commit.is_none() {
        if let Bound::Commit(c) = &bound {
            let tag_commit = ctxt
                .conn()
                .await
                .tag_to_sha(c.as_str())
                .await
                .map(Bound::Commit);
            if let Some(tag_bound) = tag_commit {
                commit = commits
                    .iter()
                    .rfind(|commit| tag_bound.right_match(master_commits, commit))
                    .cloned()
            }
        }
    }
    commit.map(ArtifactId::Commit).or_else(|| {
        data.artifacts()
            .find(|aid| match &bound {
                Bound::Commit(c) => *c == **aid,
                Bound::Date(_) => false,
                Bound::None => false,
            })
            .map(|aid| ArtifactId::Tag(aid.to_string()))
    })
}

// This is used in graphing were we want all commits on master not master_commits (which are commits on master and whole benchmark suite)
pub fn range_subset(data: Vec<Commit>, range: RangeInclusive<Bound>) -> Vec<Commit> {
    let (a, b) = range.into_inner();

    let commits_on_master: Vec<Commit> = data.iter().filter(|c| c.is_master()).cloned().collect();

    let left_idx = data
        .iter()
        .position(|commit| a.left_match(&commits_on_master, commit));
    let right_idx = data
        .iter()
        .rposition(|commit| b.right_match(&commits_on_master, commit));

    if let (Some(left), Some(right)) = (left_idx, right_idx) {
        data.get(left..=right)
            .map(|s| s.to_vec())
            .unwrap_or_else(|| {
                log::error!(
                    "Failed to compute left/right indices from {:?}..={:?}",
                    a,
                    b
                );
                vec![]
            })
    } else {
        vec![]
    }
}

impl SiteCtxt {
    pub async fn statistic_series<Q: BenchmarkQuery>(
        &self,
        query: Q,
        artifact_ids: Arc<Vec<ArtifactId>>,
    ) -> Result<Vec<SeriesResponse<Q::TestCase, StatisticSeries>>, String> {
        StatisticSeries::execute_query(artifact_ids, self, query).await
    }
}

trait StatisticSeriesExt {
    async fn execute_query<Q: BenchmarkQuery>(
        artifact_ids: Arc<Vec<ArtifactId>>,
        ctxt: &SiteCtxt,
        query: Q,
    ) -> Result<Vec<SeriesResponse<Q::TestCase, StatisticSeries>>, String>;
}

impl StatisticSeriesExt for StatisticSeries {
    async fn execute_query<Q: BenchmarkQuery>(
        artifact_ids: Arc<Vec<ArtifactId>>,
        ctxt: &SiteCtxt,
        query: Q,
    ) -> Result<Vec<SeriesResponse<Q::TestCase, Self>>, String> {
        let dumped = format!("{:?}", query);

        let index = ctxt.index.load();
        let mut conn = ctxt.conn().await;

        let start = Instant::now();
        let result = query.execute(conn.as_mut(), &index, artifact_ids).await?;
        log::trace!(
            "{:?}: run {} from {}",
            start.elapsed(),
            result.len(),
            dumped
        );
        Ok(result)
    }
}
