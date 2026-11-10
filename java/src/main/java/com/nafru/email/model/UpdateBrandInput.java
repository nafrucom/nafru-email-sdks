package com.nafru.email.model;

import java.util.List;

/**
 * Markanın TAMAMINI değiştirir: gönderilmeyen ya da {@code null} alan "ayarlanmadı" olur. Önce {@code brand().get()} ile okuyup
 * değiştirerek gönderin.
 */
public final class UpdateBrandInput extends Params<UpdateBrandInput> {
    public UpdateBrandInput logoAssetId(String value) { return set("logo_asset_id", value); }
    public UpdateBrandInput logoDarkAssetId(String value) { return set("logo_dark_asset_id", value); }
    /** px, 40–400. */
    public UpdateBrandInput logoWidth(Integer value) { return set("logo_width", value); }
    /** left, center, right. */
    public UpdateBrandInput logoAlign(String value) { return set("logo_align", value); }
    public UpdateBrandInput headerEnabled(boolean value) { return set("header_enabled", value); }
    public UpdateBrandInput accentColor(String value) { return set("accent_color", value); }
    public UpdateBrandInput textColor(String value) { return set("text_color", value); }
    public UpdateBrandInput backdropColor(String value) { return set("backdrop_color", value); }
    public UpdateBrandInput canvasColor(String value) { return set("canvas_color", value); }
    public UpdateBrandInput linkColor(String value) { return set("link_color", value); }
    /** MODERN_SANS, BOOK_SANS, ORGANIC_SANS, GEOMETRIC_SANS, HEAVY_SANS, ROUNDED_SANS, MODERN_SERIF, BOOK_SERIF, MONOSPACE. */
    public UpdateBrandInput fontFamily(String value) { return set("font_family", value); }
    /** rectangle, rounded, pill. */
    public UpdateBrandInput buttonStyle(String value) { return set("button_style", value); }
    /** px, 480–720. */
    public UpdateBrandInput contentWidth(Integer value) { return set("content_width", value); }
    public UpdateBrandInput footerText(String value) { return set("footer_text", value); }
    public UpdateBrandInput legalText(String value) { return set("legal_text", value); }
    public UpdateBrandInput postalAddress(String value) { return set("postal_address", value); }
    public UpdateBrandInput websiteUrl(String value) { return set("website_url", value); }
    public UpdateBrandInput socialLinks(List<BrandSocialLink> value) { return set("social_links", value); }
    public UpdateBrandInput unsubscribeLabel(String value) { return set("unsubscribe_label", value); }
}
