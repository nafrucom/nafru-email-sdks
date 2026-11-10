package com.nafru.email;

import com.nafru.email.model.Identified;
import com.nafru.email.model.ListResponse;
import com.nafru.email.model.Query;
import java.util.Iterator;
import java.util.NoSuchElementException;
import java.util.function.Function;

/** Liste çağrılarını tüm sayfalar boyunca gezer ({@code after} imleci). */
public final class Pagination {
    private Pagination() {}

    /**
     * Sayfaları tembel olarak çeker. Hata gelirse yineleyici {@link NafruException} fırlatır: sayfalama döngüsünde sessizce kesmek
     * eksik veri okutur.
     *
     * <pre>{@code for (Contact c : Pagination.paginate(nafru.contacts()::list, new ListContactsQuery().limit(100))) { … }}</pre>
     */
    public static <T extends Identified, Q extends Query<Q>> Iterable<T> paginate(Function<Q, ListResponse<T>> list, Q query) {
        return () -> new Iterator<>() {
            private Iterator<T> page;
            private String after;
            private boolean done;

            @Override
            public boolean hasNext() {
                while (page == null || !page.hasNext()) {
                    if (done) return false;
                    Q next = query.copy();
                    if (after != null) next.after(after);
                    ListResponse<T> response = list.apply(next);
                    var data = response.data() == null ? java.util.List.<T>of() : response.data();
                    page = data.iterator();
                    if (!response.hasMore() || data.isEmpty()) done = true;
                    else after = data.get(data.size() - 1).id();
                }
                return true;
            }

            @Override
            public T next() {
                if (!hasNext()) throw new NoSuchElementException();
                return page.next();
            }
        };
    }
}
