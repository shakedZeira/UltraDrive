# scripts/career/money.gd
class_name Money
extends RefCounted

## S7 stub credit ledger for the playable loop: add() awards event rewards,
## spend() consumes credits (repairs/upgrades land in item 11's real economy).
## Zero-sum accounting contract used by the acceptance suite: the balance is
## always exactly total credited minus total spent, and a full session that
## spends every award lands back on a zero balance (credited == spent).
## Independent of item 11's ledger backend.

var credits: int = 0

var _total_credited: int = 0
var _total_spent: int = 0

func add(amount: int) -> void:
	if amount <= 0:
		return
	credits += amount
	_total_credited += amount

## Spends credits when the balance covers the amount. Returns false (no-op)
## on insufficient funds so the session cannot go negative.
func spend(amount: int) -> bool:
	if amount <= 0 or amount > credits:
		return false
	credits -= amount
	_total_spent += amount
	return true

func get_credits() -> int:
	return credits

func get_total_credited() -> int:
	return _total_credited

func get_total_spent() -> int:
	return _total_spent

## Accounting invariant: credits always mirror credited - spent.
func is_accounting_consistent() -> bool:
	return credits == _total_credited - _total_spent

## Full-session zero-sum: everything awarded was spent back down to zero.
func balances_to_zero() -> bool:
	return credits == 0 and _total_credited == _total_spent

func reset() -> void:
	credits = 0
	_total_credited = 0
	_total_spent = 0