/// `value[key]` when [value] is a JSON object, else null. Lets nested reads stay on one line without `?[` ternaries.
Object? nrkField(Object? value, String key) => value is Map ? value[key] : null;
