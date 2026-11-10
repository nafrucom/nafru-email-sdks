use crate::error::Result;
use crate::types::{
    HasId, ListContactsQuery, ListEmailsQuery, ListEventsQuery, ListQuery, ListResponse,
    SegmentContactsQuery,
};
use std::collections::VecDeque;
use std::future::Future;

/// `after` imleci taşıyan liste sorgusu.
pub trait PageQuery {
    fn set_after(&mut self, after: String);
}

macro_rules! page_query {
    ($($name:ty),+) => {
        $(impl PageQuery for $name {
            fn set_after(&mut self, after: String) {
                self.after = Some(after);
            }
        })+
    };
}

page_query!(
    ListQuery,
    ListContactsQuery,
    ListEmailsQuery,
    ListEventsQuery,
    SegmentContactsQuery
);

/// Bir liste çağrısını tüm sayfalar boyunca gezer (`after` imleci, en yeni önce sırasında ileri).
/// Hata gelirse `next` o hatayı döner: sayfalama döngüsünde sessizce kesmek eksik veri okutur.
///
/// ```no_run
/// # async fn f(nafru: nafru_email::NafruEmail) -> nafru_email::Result<()> {
/// use nafru_email::{paginate, ListContactsQuery};
/// let mut pages = paginate(|q| nafru.contacts.list(q), ListContactsQuery { limit: Some(100), ..Default::default() });
/// while let Some(contact) = pages.next().await? {
///     println!("{}", contact.email);
/// }
/// # Ok(()) }
/// ```
pub fn paginate<T, Q, F, Fut>(list: F, query: Q) -> Paginator<T, Q, F>
where
    T: HasId,
    Q: PageQuery + Clone,
    F: FnMut(Q) -> Fut,
    Fut: Future<Output = Result<ListResponse<T>>>,
{
    Paginator {
        list,
        query,
        buffer: VecDeque::new(),
        done: false,
    }
}

pub struct Paginator<T, Q, F> {
    list: F,
    query: Q,
    buffer: VecDeque<T>,
    done: bool,
}

impl<T, Q, F, Fut> Paginator<T, Q, F>
where
    T: HasId,
    Q: PageQuery + Clone,
    F: FnMut(Q) -> Fut,
    Fut: Future<Output = Result<ListResponse<T>>>,
{
    /// Sıradaki öğe; liste bittiğinde `Ok(None)`.
    #[allow(clippy::should_implement_trait)]
    pub async fn next(&mut self) -> Result<Option<T>> {
        while self.buffer.is_empty() && !self.done {
            let page = (self.list)(self.query.clone()).await?;
            match page.data.last() {
                Some(last) if page.has_more => self.query.set_after(last.id().to_owned()),
                _ => self.done = true,
            }
            self.buffer.extend(page.data);
        }
        Ok(self.buffer.pop_front())
    }

    /// Kalan tüm öğeleri toplar.
    pub async fn collect(mut self) -> Result<Vec<T>> {
        let mut items = Vec::new();
        while let Some(item) = self.next().await? {
            items.push(item);
        }
        Ok(items)
    }
}
