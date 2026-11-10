package nafruemail

import "context"

// Pager, bir liste çağrısını tüm sayfalar boyunca gezer (bufio.Scanner gibi: Next, Item, Err).
type Pager[T any] struct {
	ctx   context.Context
	fetch func(ctx context.Context, after string) (*ListResponse[T], error)
	page  []T
	index int
	after string
	done  bool
	err   error
	item  T
}

// Paginate, after imleciyle (son öğenin id'si) sayfaları sırayla ister. Hata gelirse gezinme durur ve Err döner:
// sayfalama döngüsünde sessizce kesmek eksik veri okutur.
//
//	pager := nafru.Paginate(ctx, func(ctx context.Context, after string) (*nafru.ListResponse[nafru.Contact], error) {
//		return client.Contacts.List(ctx, &nafru.ListContactsQuery{ListQuery: nafru.ListQuery{Limit: 100, After: after}})
//	})
//	for pager.Next() { fmt.Println(pager.Item().Email) }
//	if err := pager.Err(); err != nil { ... }
func Paginate[T any](ctx context.Context, fetch func(ctx context.Context, after string) (*ListResponse[T], error)) *Pager[T] {
	return &Pager[T]{ctx: ctx, fetch: fetch}
}

// Next sıradaki öğeye geçer; bitti ya da hata olduysa false.
func (p *Pager[T]) Next() bool {
	for p.index >= len(p.page) {
		if p.done || p.err != nil {
			return false
		}
		response, err := p.fetch(p.ctx, p.after)
		if err != nil {
			p.err = err
			return false
		}
		p.page, p.index = response.Data, 0
		if !response.HasMore || response.lastID == "" {
			p.done = true
		}
		p.after = response.lastID
	}
	p.item = p.page[p.index]
	p.index++
	return true
}

// Item, Next'in ilerlediği öğedir.
func (p *Pager[T]) Item() T { return p.item }

// Err, gezinmeyi durduran hatadır (*Error); sorunsuz bittiyse nil.
func (p *Pager[T]) Err() error { return p.err }
