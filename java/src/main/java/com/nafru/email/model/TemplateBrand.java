package com.nafru.email.model;

/**
 * Şablonun marka kipi: {@code inherit} marka olduğu gibi, {@code custom} marka + {@code override}, {@code none} hiçbir şey eklenmez.
 * Pazarlama şablonunda {@code custom} ile {@code showFooter=false} 422 verir: altbilgi çıkma bağlantısını taşır.
 */
public record TemplateBrand(String mode, TemplateBrandOverride override) {
    public static TemplateBrand of(String mode) {
        return new TemplateBrand(mode, null);
    }
}
