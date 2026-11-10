package com.nafru.email;

import com.nafru.email.model.Brand;
import com.nafru.email.model.UpdateBrandInput;

/** Çalışma alanının markası: logo, renkler, yazı tipi, altbilgi. Şablonlar markayı {@code brand} alanıyla devralır. */
public final class BrandResource {
    private final Http.Caller http;

    BrandResource(Http.Caller http) { this.http = http; }

    public Brand get() {
        return http.call(Http.Request.get("/brand"), Brand.class);
    }

    /** Markanın TAMAMINI değiştirir (gönderilmeyen alan "ayarlanmadı" olur). */
    public Brand update(UpdateBrandInput input) {
        return http.call(Http.Request.put("/brand", input), Brand.class);
    }
}
