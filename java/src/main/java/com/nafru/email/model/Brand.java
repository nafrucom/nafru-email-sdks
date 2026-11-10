package com.nafru.email.model;

import java.util.List;

/** Çalışma alanının markası. Ayarlanmamış renk/yazı tipi/genişlik varsayılanla döner; marka hiç kaydedilmediyse {@code configured=false}. */
public record Brand(
        String object,
        boolean configured,
        String logoAssetId,
        String logoUrl,
        String logoDarkAssetId,
        String logoDarkUrl,
        int logoWidth,
        String logoAlign,
        boolean headerEnabled,
        String accentColor,
        String textColor,
        String backdropColor,
        String canvasColor,
        String linkColor,
        String fontFamily,
        String buttonStyle,
        int contentWidth,
        String footerText,
        String legalText,
        String postalAddress,
        String websiteUrl,
        List<BrandSocialLink> socialLinks,
        String unsubscribeLabel,
        String updatedAt) {}
