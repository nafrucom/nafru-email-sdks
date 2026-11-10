using System.Runtime.CompilerServices;

namespace Nafru.Email;

public static class NafruPagination
{
    /// <summary>
    /// Bir liste çağrısını tüm sayfalar boyunca gezer (<c>After</c> imleci, en yeni önce sırasında ileri). Hata gelirse <see cref="NafruException"/>
    /// fırlatır: sayfalama döngüsünde sessizce kesmek eksik veri okutur.
    /// <code>await foreach (var contact in NafruPagination.PaginateAsync(nafru.Contacts.ListAsync, new ListContactsQuery { Limit = 100 })) { }</code>
    /// </summary>
    public static async IAsyncEnumerable<T> PaginateAsync<T, TQuery>(
        Func<TQuery, CancellationToken, Task<ListResponse<T>>> list,
        TQuery query,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
        where T : IHasId
        where TQuery : ListQuery
    {
        string? after = null;
        while (true)
        {
            var page = await list((TQuery)((ListQuery)query with { After = after, Before = null }), cancellationToken).ConfigureAwait(false);
            foreach (var item in page.Data) yield return item;
            if (!page.HasMore || page.Data.Count == 0) yield break;
            after = page.Data[^1].Id;
        }
    }
}
