import classy, options, future

# We have to define a typeclass before we can create instances.
# Parts of declaration:
# - `Monoid` - name of the typeclass being defined
# - `M` - placeholder for typeclass member
# - `exported` declaration makes typeclass accessible from another modules
#
# Notice that `mempty` and `mappend` are not defined. These should be
# implemented by user before instantiating typeclass.
typeclass Monoid, M, exported:
  # proc mempty(t: typedesc[M]): M
  # proc mappend(a, b: M): M

  # Marker proc to be used later
  proc isMonoid(_: typedesc[M]) = discard
  proc mconcat(ms: varargs[M]): M =
    result = mempty(M)
    for m in ms:
      result = mappend(result, m)

# We can now define `Monoid` instances for any types we want
proc mempty(t = string): string = ""
proc mappend(a, b: string): string = a & b

# For `string` we can write optimized `mconcat` implementation.
proc mconcat(ss: varargs[string]): string =
  result = ""
  for s in ss: result.add(s)

# - `skipping(a, b, ...)` stops the macro from instantiating
# corresponding declarations. Notice that other procs in
# the typeclass might rely on the skipped ones, so be sure to
# declare your implementations before instantiating a typeclass.
# - `exporting(a, b, ...)` adds export marks to corresponding
# proc declarations; `exporting(_)` exports all the defined procs.
instance Monoid, string, skipping(mconcat)
assert compiles(string.isMonoid)

# We can leverage nim's concepts and type unions in our instances
proc mempty[T: SomeNumber](_: typedesc[T]): T = T(0)
proc mappend[T: SomeNumber](a, b: T): T = a + b
instance Monoid, (T: SomeNumber) => T

assert mconcat([1, 2, 3]) == 6
assert mconcat([0.5, 0.5]) == 1.0

# This means we can, to some extent, "derive" instances (if we have proper
# concepts defined).
type
  MonoidConcept = concept x
    # It was defined in typeclass
    isMonoid(type(x))
assert: string is MonoidConcept
assert: not (bool is MonoidConcept)

proc mempty[T: MonoidConcept](t: typedesc[Option[T]]): Option[T] =
  some(mempty(T))
proc mappend[T: MonoidConcept](a, b: Option[T]): Option[T] =
  if a.isNone: b
  elif b.isNone: a
  else:
    some(mappend(a.get, b.get))
instance Monoid, (T: MonoidConcept) => Option[T]
assert: mconcat(@[some("foo"), some("bar")]) == some("foobar")
# Works for Option[Option[string]] too!
assert: mconcat(@[some(some("foo")), some(none(string)), some(some("bar"))]) == some(some("foobar"))

# Everything up to this point, however, could be just as easily done
# with generics: indeed, it would be enough to define `mconcat`
# like this:
#
# .. code-block
#
#   proc mconcat[T: MonoidConcept](a, b: T): T = ...
#
# and add corresponding `isMonoid` definitions.
#
# There is, however, something that is out of reach for Nim generics:
# we can't abstract over type constructors. Classy was created for this
# exact use case:

typeclass Functor, F[_]:
  # Again, can't forward-declare this.
  # proc fmap[A, B](fa: F[A], g: A -> B): F[B]

  proc `$>`[A, B](fa: F[A], b: B): F[B] =
    fmap(fa, (a: A) => b)


proc fmap[A, B](fa: Option[A], g: A -> B): Option[B] =
  fa.map(g)

# Notice that `Option` is not a type: it is a type **constructor**. All
# occurrences of the form `F[X]` in the typeclass body will be replaced
# with `Option[X]`.
instance Functor, Option[_]

assert: (some("foo") $> 123) == some(123)

# All previously mentioned features still work, so you can, for
# example, write something like this:
#
# .. code-block
#
#   instance Monad, A => Either[A, _]
#
# (after, of course, defining a suitable `Monad` typeclass)

# We can also define typeclasses with multiple parameters:
typeclass TraversableInst, [T[_], F[_]]:
  # proc traverse[A, B](ta: T[A], f: A -> F[B]): F[B]
  proc sequence[A](tfa: T[F[A]]): F[T[A]] =
    traverse(tfa, (fa: F[A]) => fa)

# Notice that this is not `Traversable` in its proper form - we have
# to use a separate instance for each applicative functor `F`.


# We should use `Applicative` typeclass for this, but this is just an
# example
proc pure[A](ta: typedesc[Option[A]], a: A): Option[A] = some(a)
proc `<*>`[A, B](fg: Option[A -> B], fa: Option[A]): Option[B] =
  if fg.isSome and fa.isSome:
    some(fg.get()(fa.get()))
  else:
    none(B)

# We can define a `traverse` for `seq` and `Option` and be done with
# it, but we'd have to duplicate the definition for each functor we want to
# use. This does not seem pleasant.
#
# Let's try another approach:

typeclass TraverseSeqWith, F[_]:
  proc traverse[A, B](ta: seq[A], f: A -> F[B]): F[seq[B]] =
    result = pure(F[seq[B]], newSeq[B]())
    let worker: (seq[B] -> (B -> seq[B])) = (bs: seq[B]) => ((b: B) => bs & b)
    for a in ta:
      result = pure(F[type(worker)], worker) <*> result <*> f(a)

  instance TraversableInst, [seq[_], F[_]]

# Now we only have to duplicate this line to support a new functor.
instance TraverseSeqWith, Option[_]

assert: sequence(@[1.some, 2.some, 3.some]) == some(@[1, 2, 3])
assert: sequence(@[1.some, none(int), 3.some]) == none(seq[int])
