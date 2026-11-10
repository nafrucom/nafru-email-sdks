package com.nafru.email.model;

/** İmleçli liste sorgusu: {@code after} ve {@code before} birlikte verilemez. */
public abstract class Query<S extends Query<S>> extends Params<S> {
    /** 1–100, varsayılan 20. */
    public S limit(int limit) { return set("limit", limit); }

    /** Bu kimlikten sonraki kayıtlar. */
    public S after(String after) { return set("after", after); }

    /** Bu kimlikten önceki kayıtlar. */
    public S before(String before) { return set("before", before); }

    /** Sayfalama için kopya (kullanıcının sorgu nesnesi değişmez). */
    @SuppressWarnings("unchecked")
    public S copy() {
        try {
            S copy = (S) getClass().getDeclaredConstructor().newInstance();
            toMap().forEach(copy::put);
            return copy;
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException("Sorgu kopyalanamadı: " + getClass().getName(), e);
        }
    }
}
