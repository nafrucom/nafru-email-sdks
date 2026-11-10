package com.nafru.email;

import com.nafru.email.model.CreateTemplateInput;
import com.nafru.email.model.Deleted;
import com.nafru.email.model.ListQuery;
import com.nafru.email.model.ListResponse;
import com.nafru.email.model.PutTemplateTranslationInput;
import com.nafru.email.model.Ref;
import com.nafru.email.model.Template;
import com.nafru.email.model.TemplatePublished;
import com.nafru.email.model.TemplateSaved;
import com.nafru.email.model.TemplateTranslation;
import com.nafru.email.model.TemplateTranslationDeleted;
import com.nafru.email.model.UpdateTemplateInput;

/** {@code idOrAlias}: kimlik ya da takma ad. */
public final class Templates {
    private final Http.Caller http;

    Templates(Http.Caller http) { this.http = http; }

    private static String path(String idOrAlias) { return "/templates/" + Http.seg(idOrAlias); }

    public TemplateSaved create(CreateTemplateInput input) {
        return http.call(Http.Request.post("/templates", input), TemplateSaved.class);
    }

    public Template get(String idOrAlias) {
        return http.call(Http.Request.get(path(idOrAlias)), Template.class);
    }

    public ListResponse<Template> list() { return list(new ListQuery()); }

    public ListResponse<Template> list(ListQuery query) {
        return http.call(Http.Request.get("/templates", query.toMap()), Json.listOf(Template.class));
    }

    /** Taslağı kaydeder; yayımlanana kadar gönderimler eski sürümü kullanır. */
    public TemplateSaved update(String idOrAlias, UpdateTemplateInput input) {
        return http.call(Http.Request.patch(path(idOrAlias), input), TemplateSaved.class);
    }

    public Deleted remove(String idOrAlias) {
        return http.call(Http.Request.delete(path(idOrAlias)), Deleted.class);
    }

    public TemplatePublished publish(String idOrAlias) {
        return http.call(Http.Request.post(path(idOrAlias) + "/publish", null), TemplatePublished.class);
    }

    public Ref duplicate(String idOrAlias) {
        return http.call(Http.Request.post(path(idOrAlias) + "/duplicate", null), Ref.class);
    }

    /** Dil taslağını yazar; gönderimler bir sonraki yayından itibaren bu dili kullanır. */
    public TemplateTranslation putTranslation(String idOrAlias, String locale, PutTemplateTranslationInput input) {
        return http.call(Http.Request.put(path(idOrAlias) + "/translations/" + Http.seg(locale), input), TemplateTranslation.class);
    }

    public TemplateTranslationDeleted removeTranslation(String idOrAlias, String locale) {
        return http.call(Http.Request.delete(path(idOrAlias) + "/translations/" + Http.seg(locale)), TemplateTranslationDeleted.class);
    }
}
