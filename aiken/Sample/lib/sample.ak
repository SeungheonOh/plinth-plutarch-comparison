/// `Amount n` = `Constr 0 [I n]`, `Joint x y` = `Constr 1 [x, y]`,
/// `Deduct n from` = `Constr 2 [I n, from]`.
pub type Withdraw {
  Amount(Int)
  Joint(Withdraw, Withdraw)
  Deduct(Int, Withdraw)
}

fn net(w: Withdraw) -> Int {
  when w is {
    Amount(n) -> n
    Joint(x, y) -> net(x) + net(y)
    Deduct(n, from) -> net(from) - n
  }
}

/// Net amount withdrawn. The argument arrives as `Data` and is decoded lazily
/// while it is traversed, without a separate up-front validation pass.
pub fn net_withdraw(w: Withdraw) -> Int {
  net(w)
}
