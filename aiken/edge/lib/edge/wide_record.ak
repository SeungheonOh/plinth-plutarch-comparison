pub type Wide {
  Wide {
    f0: Int,
    f1: Int,
    f2: Int,
    f3: Int,
    f4: Int,
    f5: Int,
    f6: Int,
    f7: Int,
    f8: Int,
    f9: Int,
    f10: Int,
    f11: Int,
  }
}

/// Sum of the first, middle and last fields of a twelve-field record.
pub fn wide_record(record: Wide) -> Int {
  record.f0 + record.f6 + record.f11
}
