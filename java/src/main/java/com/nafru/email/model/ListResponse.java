package com.nafru.email.model;

import java.util.List;

/** Sunucunun {@code { object: 'list', data, has_more }} liste zarfı. */
public record ListResponse<T>(String object, List<T> data, boolean hasMore) {}
