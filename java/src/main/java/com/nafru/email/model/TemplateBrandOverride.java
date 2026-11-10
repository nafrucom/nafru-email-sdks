package com.nafru.email.model;

/** Şablon başına markayı ezen alanlar (yalnız {@code custom} kipte); {@code null} alanlar gönderilmez. */
public record TemplateBrandOverride(
        String accentColor,
        String textColor,
        String backdropColor,
        String canvasColor,
        String fontFamily,
        String linkColor,
        Integer contentWidth,
        Boolean showHeader,
        Boolean showFooter) {}
