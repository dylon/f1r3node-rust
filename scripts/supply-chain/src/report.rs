use std::collections::{BTreeMap, BTreeSet};

use serde_json::{Map, Value};

use crate::policy::Exception;
use crate::CHECKS;

#[derive(Default, Debug)]
pub struct Report {
    pub errors: Vec<String>,
    pub encountered: BTreeSet<String>,
}

fn reviewed_diagnostic(
    fields: &Map<String, Value>,
    exceptions: &BTreeMap<String, Exception>,
    result: &mut Report,
) {
    let yanked = fields.get("code").and_then(Value::as_str) == Some("yanked-ignored");
    let id = if yanked {
        fields
            .get("labels")
            .and_then(Value::as_array)
            .and_then(|labels| {
                labels.iter().find_map(|label| {
                    (label.get("message").and_then(Value::as_str) == Some("yanked ignore"))
                        .then(|| label.get("span").and_then(Value::as_str))
                        .flatten()
                })
            })
    } else if let Some(advisory) = fields.get("advisory") {
        advisory.get("id").and_then(Value::as_str)
    } else {
        return;
    };
    let Some(id) = id.filter(|id| !id.is_empty()) else {
        result
            .errors
            .push("The scanner produced an invalid reviewed exception record.".into());
        return;
    };
    let Some(exception) = exceptions.get(id) else {
        if yanked {
            result
                .errors
                .push(format!("{id}: the yanked crate has no reviewed exception."));
        }
        return;
    };
    result.encountered.insert(id.into());
    let Some(graphs) = fields
        .get("graphs")
        .and_then(Value::as_array)
        .filter(|g| !g.is_empty())
    else {
        result.errors.push(format!(
            "{id}: the scanner did not identify an affected package."
        ));
        return;
    };
    for graph in graphs {
        let Some(package) = graph.get("Krate").and_then(Value::as_object) else {
            result.errors.push(format!(
                "{id}: the scanner produced an invalid package record."
            ));
            continue;
        };
        if package.get("name").and_then(Value::as_str) != Some(&exception.package)
            || !package
                .get("version")
                .and_then(Value::as_str)
                .is_some_and(|v| exception.versions.iter().any(|allowed| allowed == v))
        {
            result.errors.push(format!(
                "{id}: the reviewed exception does not cover this package version."
            ));
        }
    }
}

pub fn validate(text: &str, exceptions: &BTreeMap<String, Exception>) -> Report {
    let mut result = Report::default();
    let mut summary = None;
    for line in text.lines() {
        let record = serde_json::from_str::<Value>(line).unwrap_or(Value::Null);
        let Some(fields) = record.get("fields").and_then(Value::as_object) else {
            result
                .errors
                .push("The scanner produced an invalid JSON record.".into());
            continue;
        };
        if record.get("type").and_then(Value::as_str) == Some("summary")
            && summary.replace(fields.clone()).is_some()
        {
            result
                .errors
                .push("The scanner reported multiple summaries.".into());
        }
        if matches!(
            fields.get("severity").and_then(Value::as_str),
            Some("error" | "bug")
        ) || fields.get("level").and_then(Value::as_str) == Some("ERROR")
        {
            result.errors.push(format!(
                "{}: {}",
                fields
                    .get("code")
                    .and_then(Value::as_str)
                    .unwrap_or("scanner"),
                fields
                    .get("message")
                    .and_then(Value::as_str)
                    .unwrap_or("scanner failure")
            ));
        }
        reviewed_diagnostic(fields, exceptions, &mut result);
    }
    match summary {
        Some(summary)
            if summary.len() == CHECKS.len()
                && CHECKS.iter().all(|check| summary.contains_key(*check)) =>
        {
            for check in CHECKS {
                match summary[check].get("errors").and_then(Value::as_u64) {
                    Some(0) => (),
                    Some(_) => result
                        .errors
                        .push(format!("The scanner reported a failed {check} check.")),
                    None => result
                        .errors
                        .push("The scanner reported invalid check statistics.".into()),
                }
            }
        }
        _ => result
            .errors
            .push("The scanner must report all four checks.".into()),
    }
    result
}
