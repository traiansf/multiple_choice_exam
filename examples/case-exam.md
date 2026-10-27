# Software Design — Final

## Requirements

### Case: a lending library

A member may request a title that has **no available copies**. Requests are
served in the order they were made:

| Rule | Text |
|------|------|
| R1 | When a copy is returned, it is reserved for the oldest pending request. |
| R2 | Only the member who made the request may pick up the reserved copy. |

#### A copy is returned while two requests are pending. Which request gets it?
- [ ] The most recent one
- [x] The oldest one
- [ ] Whichever member arrives first
- [ ] Neither; the copy goes back on the shelf

#### Another member tries to pick up the reserved copy. What happens?
- [ ] The pickup succeeds and the request is closed
- [ ] The pickup succeeds and the request stays pending
- [x] The pickup is refused
- [ ] The reservation is cancelled

### Which kind of requirement is "searches answer within 2 seconds"?
- [ ] Functional
- [ ] Domain rule
- [x] Quality attribute
- [ ] Constraint

## Contracts

### Case: a bounded counter

A counter starts at `0`. The operation `inc()` adds one; it is allowed only
while the value is below `10`.

#### Which statement is an invariant of the counter?
- [x] `0 <= value <= 10`
- [ ] `value == 0`
- [ ] `value < 10`
- [ ] `inc()` may always be called

#### What is the precondition of `inc()`?
- [ ] `value >= 0`
- [x] `value < 10`
- [ ] `value == 10`
- [ ] none
