import Foundation

// Şablonlar ve marka.

/// Şablon başına markayı ezen alanlar (yalnız `custom` kipte).
public struct TemplateBrandOverride: Codable, Sendable {
    public var accentColor: String?
    public var textColor: String?
    public var backdropColor: String?
    public var canvasColor: String?
    public var fontFamily: String?
    public var linkColor: String?
    public var contentWidth: Int?
    public var showHeader: Bool?
    public var showFooter: Bool?

    public init(
        accentColor: String? = nil, textColor: String? = nil, backdropColor: String? = nil, canvasColor: String? = nil,
        fontFamily: String? = nil, linkColor: String? = nil, contentWidth: Int? = nil, showHeader: Bool? = nil, showFooter: Bool? = nil
    ) {
        self.accentColor = accentColor
        self.textColor = textColor
        self.backdropColor = backdropColor
        self.canvasColor = canvasColor
        self.fontFamily = fontFamily
        self.linkColor = linkColor
        self.contentWidth = contentWidth
        self.showHeader = showHeader
        self.showFooter = showFooter
    }

    enum CodingKeys: String, CodingKey {
        case accentColor = "accent_color"
        case textColor = "text_color"
        case backdropColor = "backdrop_color"
        case canvasColor = "canvas_color"
        case fontFamily = "font_family"
        case linkColor = "link_color"
        case contentWidth = "content_width"
        case showHeader = "show_header"
        case showFooter = "show_footer"
    }
}

/// Şablonun marka kipi: `inherit` marka olduğu gibi, `custom` marka + `override`, `none` hiçbir şey eklenmez.
/// Pazarlama şablonunda `custom` ile `showFooter: false` 422 verir: altbilgi çıkma bağlantısını taşır.
public struct TemplateBrand: Codable, Sendable {
    public var mode: String
    public var override: TemplateBrandOverride?

    public init(mode: String, override: TemplateBrandOverride? = nil) {
        self.mode = mode
        self.override = override
    }
}

public struct TemplateListItem: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let alias: String?
    /// `design` ya da `html`.
    public let type: String
    /// `draft` ya da `published`.
    public let status: String
    public let subject: String?
    public let currentVersion: Int?
    public let hasUnpublishedChanges: Bool
    public let publishedAt: String?
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, alias, type, status, subject
        case currentVersion = "current_version"
        case hasUnpublishedChanges = "has_unpublished_changes"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Şablonda kullanılan değişken: `{{{AD}}}` ya da `{{{AD|yedek}}}`.
public struct TemplateVariable: Decodable, Sendable {
    public let key: String
    public let type: String
    public let fallbackValue: String?

    enum CodingKeys: String, CodingKey {
        case key, type
        case fallbackValue = "fallback_value"
    }
}

public struct Template: Decodable, Sendable, Identifiable {
    public let object: String
    public let id: String
    public let name: String
    public let alias: String?
    public let type: String
    public let status: String
    public let subject: String?
    public let currentVersion: Int?
    public let hasUnpublishedChanges: Bool
    public let publishedAt: String?
    public let createdAt: String
    public let updatedAt: String
    public let previewText: String?
    public let html: String
    public let text: String?
    public let design: JSONValue?
    public let revision: Int
    public let variables: [TemplateVariable]
    public let brand: TemplateBrand

    enum CodingKeys: String, CodingKey {
        case object, id, name, alias, type, status, subject, html, text, design, revision, variables, brand
        case currentVersion = "current_version"
        case hasUnpublishedChanges = "has_unpublished_changes"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case previewText = "preview_text"
    }
}

public struct CreateTemplateInput: Encodable, Sendable {
    public var name: String
    public var alias: String?
    public var subject: String??
    public var previewText: String??
    public var html: String
    public var text: String??
    /// Varsayılan `none`: HTML olduğu gibi kalır.
    public var brand: TemplateBrand?

    public init(name: String, alias: String? = nil, subject: String?? = nil, previewText: String?? = nil, html: String, text: String?? = nil, brand: TemplateBrand? = nil) {
        self.name = name
        self.alias = alias
        self.subject = subject
        self.previewText = previewText
        self.html = html
        self.text = text
        self.brand = brand
    }

    enum CodingKeys: String, CodingKey {
        case name, alias, subject, html, text, brand
        case previewText = "preview_text"
    }
}

public struct UpdateTemplateInput: Encodable, Sendable {
    /// Eşzamanlı düzenleme denetimi: önceki okumadaki `revision`.
    public var revision: Int?
    public var name: String?
    public var alias: String??
    public var subject: String??
    public var previewText: String??
    public var html: String?
    public var text: String??
    public var brand: TemplateBrand?

    public init(
        revision: Int? = nil, name: String? = nil, alias: String?? = nil, subject: String?? = nil, previewText: String?? = nil,
        html: String? = nil, text: String?? = nil, brand: TemplateBrand? = nil
    ) {
        self.revision = revision
        self.name = name
        self.alias = alias
        self.subject = subject
        self.previewText = previewText
        self.html = html
        self.text = text
        self.brand = brand
    }

    enum CodingKeys: String, CodingKey {
        case revision, name, alias, subject, html, text, brand
        case previewText = "preview_text"
    }
}

public struct TemplateSaved: Decodable, Sendable {
    public let object: String
    public let id: String
    public let revision: Int
}

public struct TemplatePublished: Decodable, Sendable {
    public let object: String
    public let id: String
    public let version: Int
    public let versionId: String
    public let revision: Int

    enum CodingKeys: String, CodingKey {
        case object, id, version, revision
        case versionId = "version_id"
    }
}

/// Bir dilin taslağı. API anahtarıyla yalnız `html` türü şablonda; `locale` BCP 47, ana dile indirgenir.
public struct PutTemplateTranslationInput: Encodable, Sendable {
    public var subject: String??
    public var previewText: String??
    public var html: String
    public var text: String??

    public init(subject: String?? = nil, previewText: String?? = nil, html: String, text: String?? = nil) {
        self.subject = subject
        self.previewText = previewText
        self.html = html
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case subject, html, text
        case previewText = "preview_text"
    }
}

public struct TemplateTranslation: Decodable, Sendable {
    public let locale: String
    public let subject: String?
    public let previewText: String?
    public let designRevision: Int
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case locale, subject
        case previewText = "preview_text"
        case designRevision = "design_revision"
        case updatedAt = "updated_at"
    }
}

public struct TemplateTranslationDeleted: Decodable, Sendable {
    public let object: String
    public let locale: String
    public let deleted: Bool
}

public struct BrandSocialLink: Codable, Sendable {
    /// `website`, `x`, `facebook`, `instagram`, `linkedin`, `youtube`, `github`, `tiktok`.
    public var network: String
    /// http(s) adresi.
    public var url: String

    public init(network: String, url: String) {
        self.network = network
        self.url = url
    }
}

/// Çalışma alanının markası. Ayarlanmamış renk/yazı tipi/genişlik varsayılan değerle döner.
public struct Brand: Decodable, Sendable {
    public let object: String
    public let configured: Bool
    public let logoAssetId: String?
    public let logoUrl: String?
    public let logoDarkAssetId: String?
    public let logoDarkUrl: String?
    public let logoWidth: Int
    public let logoAlign: String
    public let headerEnabled: Bool
    public let accentColor: String
    public let textColor: String
    public let backdropColor: String
    public let canvasColor: String
    public let linkColor: String
    public let fontFamily: String
    public let buttonStyle: String
    public let contentWidth: Int
    public let footerText: String?
    public let legalText: String?
    public let postalAddress: String?
    public let websiteUrl: String?
    public let socialLinks: [BrandSocialLink]
    public let unsubscribeLabel: String
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case object, configured
        case logoAssetId = "logo_asset_id"
        case logoUrl = "logo_url"
        case logoDarkAssetId = "logo_dark_asset_id"
        case logoDarkUrl = "logo_dark_url"
        case logoWidth = "logo_width"
        case logoAlign = "logo_align"
        case headerEnabled = "header_enabled"
        case accentColor = "accent_color"
        case textColor = "text_color"
        case backdropColor = "backdrop_color"
        case canvasColor = "canvas_color"
        case linkColor = "link_color"
        case fontFamily = "font_family"
        case buttonStyle = "button_style"
        case contentWidth = "content_width"
        case footerText = "footer_text"
        case legalText = "legal_text"
        case postalAddress = "postal_address"
        case websiteUrl = "website_url"
        case socialLinks = "social_links"
        case unsubscribeLabel = "unsubscribe_label"
        case updatedAt = "updated_at"
    }
}

/// `brand.update` markanın TAMAMINI değiştirir: gönderilmeyen alan "ayarlanmadı" olur. Önce `brand.get` ile okuyup değiştirin.
public struct UpdateBrandInput: Encodable, Sendable {
    public var logoAssetId: String?
    public var logoDarkAssetId: String?
    public var logoWidth: Int?
    public var logoAlign: String?
    public var headerEnabled: Bool?
    public var accentColor: String?
    public var textColor: String?
    public var backdropColor: String?
    public var canvasColor: String?
    public var linkColor: String?
    public var fontFamily: String?
    public var buttonStyle: String?
    public var contentWidth: Int?
    public var footerText: String?
    public var legalText: String?
    public var postalAddress: String?
    public var websiteUrl: String?
    public var socialLinks: [BrandSocialLink]?
    public var unsubscribeLabel: String?

    public init(
        logoAssetId: String? = nil, logoDarkAssetId: String? = nil, logoWidth: Int? = nil, logoAlign: String? = nil,
        headerEnabled: Bool? = nil, accentColor: String? = nil, textColor: String? = nil, backdropColor: String? = nil,
        canvasColor: String? = nil, linkColor: String? = nil, fontFamily: String? = nil, buttonStyle: String? = nil,
        contentWidth: Int? = nil, footerText: String? = nil, legalText: String? = nil, postalAddress: String? = nil,
        websiteUrl: String? = nil, socialLinks: [BrandSocialLink]? = nil, unsubscribeLabel: String? = nil
    ) {
        self.logoAssetId = logoAssetId
        self.logoDarkAssetId = logoDarkAssetId
        self.logoWidth = logoWidth
        self.logoAlign = logoAlign
        self.headerEnabled = headerEnabled
        self.accentColor = accentColor
        self.textColor = textColor
        self.backdropColor = backdropColor
        self.canvasColor = canvasColor
        self.linkColor = linkColor
        self.fontFamily = fontFamily
        self.buttonStyle = buttonStyle
        self.contentWidth = contentWidth
        self.footerText = footerText
        self.legalText = legalText
        self.postalAddress = postalAddress
        self.websiteUrl = websiteUrl
        self.socialLinks = socialLinks
        self.unsubscribeLabel = unsubscribeLabel
    }

    enum CodingKeys: String, CodingKey {
        case logoAssetId = "logo_asset_id"
        case logoDarkAssetId = "logo_dark_asset_id"
        case logoWidth = "logo_width"
        case logoAlign = "logo_align"
        case headerEnabled = "header_enabled"
        case accentColor = "accent_color"
        case textColor = "text_color"
        case backdropColor = "backdrop_color"
        case canvasColor = "canvas_color"
        case linkColor = "link_color"
        case fontFamily = "font_family"
        case buttonStyle = "button_style"
        case contentWidth = "content_width"
        case footerText = "footer_text"
        case legalText = "legal_text"
        case postalAddress = "postal_address"
        case websiteUrl = "website_url"
        case socialLinks = "social_links"
        case unsubscribeLabel = "unsubscribe_label"
    }
}
