{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE UndecidableInstances #-} -- allows the TypeRep default

{- |

This module implements an interface for working with "tries".
A key in the trie represents a distinct path through the trie.
This can provide benefits when using very large and possibly
very similar keys where comparing for order can become
expensive, and storing the various keys could be inefficient.

For primitive types like 'Int', this library will select efficient
implementations automatically.

All methods of 'TrieKey' can be derived automatically using
a 'Generic' instance.

@
data Demo = DemoC1 'Int' | DemoC2 'Int' 'Char'  deriving 'Generic'

instance 'TrieKey' Demo
@

-}

module Data.GenericTrie
  (
  -- * Trie interface
    Trie(..)
  , alter
  , member
  , notMember
  , fromList
  , toList
  , TrieKey(..)
  -- * Generic derivation implementation
  , genericTrieNull
  , genericTrieMap
  , genericTrieFold
  , genericTrieTraverse
  , genericTrieShowsPrec
  , genericInsert
  , genericLookup
  , genericDelete
  , genericSelect
  , genericMapMaybe
  , genericSingleton
  , genericEmpty
  , genericFoldWithKey
  , genericTraverseWithKey
  , TrieRepDefault
  , GTrieKey(..)
  , GTrie(..)
  ) where


import Control.Applicative (Applicative, liftA2)
import Data.Char (chr, ord)
import Data.Foldable (Foldable)
import Data.Functor.Compose (Compose(..))
import Data.IntMap (IntMap)
import Data.List (foldl')
import Data.Map (Map)
import Data.Maybe (isNothing, isJust)
import Data.Traversable (Traversable,traverse)
import GHC.Generics
import Prelude hiding (lookup)
import qualified Data.Foldable as Foldable
import qualified Data.IntMap as IntMap
import qualified Data.Map as Map


-- | Keys that support prefix-trie map operations.
--
-- All operations can be automatically derived from a 'Generic' instance.
class TrieKey k where

  -- | Type of the representation of tries for this key.
  type TrieRep k :: * -> *

  -- | Construct an empty trie
  empty :: Trie k a

  -- | Test for an empty trie
  trieNull :: Trie k a -> Bool

  -- | Lookup element from trie
  lookup :: k -> Trie k a -> Maybe a

  -- | Insert element into trie
  insert :: k -> a -> Trie k a -> Trie k a

  -- | Delete element from trie
  delete :: k -> Trie k a -> Trie k a

  -- | Construct a trie holding a single value
  singleton :: k -> a -> Trie k a

  -- | Apply a function to all values stored in a trie
  trieMap :: (a -> b) -> Trie k a -> Trie k b

  -- | Fold all the values stored in a trie
  trieFold :: (a -> b -> b) -> Trie k a -> b -> b

  -- | Traverse the values stored in a trie
  trieTraverse :: Applicative f => (a -> f b) -> Trie k a -> f (Trie k b)

  -- | Show the representation of a trie
  trieShowsPrec :: Show a => Int -> Trie k a -> ShowS

  -- | Select a subtree of the 'Trie'. This is intended to support
  -- types with a "wildcard" key for doing more interesting filtering.
  select :: k -> Trie k a -> Trie k a

  -- | Apply a function to the values of a 'Trie' and keep the elements
  -- of the trie that result in a 'Just' value.
  mapMaybe :: (a -> Maybe b) -> Trie k a -> Trie k b

  -- | Fold a trie with a function of both key and value.
  foldWithKey :: (k -> a -> r -> r) -> r -> Trie k a -> r

  -- | Traverse a trie with a function of both key and value.
  traverseWithKey :: Applicative f => (k -> a -> f b) -> Trie k a -> f (Trie k b)


  -- Defaults using 'Generic'

  type instance TrieRep k = TrieRepDefault k

  default empty :: ( TrieRep k ~ TrieRepDefault k) => Trie k a
  empty = genericEmpty

  default singleton ::
    ( GTrieKey (Rep k), Generic k , TrieRep k ~ TrieRepDefault k) =>
    k -> a -> Trie k a
  singleton = genericSingleton

  default trieNull ::
    ( TrieRep k ~ TrieRepDefault k) =>
    Trie k a -> Bool
  trieNull = genericTrieNull

  default lookup ::
    ( GTrieKey (Rep k), Generic k , TrieRep k ~ TrieRepDefault k) =>
    k -> Trie k a -> Maybe a
  lookup = genericLookup

  default insert ::
    ( GTrieKey (Rep k), Generic k , TrieRep k ~ TrieRepDefault k) =>
    k -> a -> Trie k a -> Trie k a
  insert = genericInsert

  default delete ::
    ( GTrieKey (Rep k), Generic k , TrieRep k ~ TrieRepDefault k) =>
    k -> Trie k a -> Trie k a
  delete = genericDelete

  default trieMap ::
    ( GTrieKey (Rep k) , TrieRep k ~ TrieRepDefault k) =>
    (a -> b) -> Trie k a -> Trie k b
  trieMap = genericTrieMap

  default trieFold ::
    ( GTrieKey (Rep k) , TrieRep k ~ TrieRepDefault k) =>
    (a -> b -> b) -> Trie k a -> b -> b
  trieFold = genericTrieFold

  default trieTraverse ::
    ( GTrieKey (Rep k) , TrieRep k ~ TrieRepDefault k , Applicative f) =>
    (a -> f b) -> Trie k a -> f (Trie k b)
  trieTraverse = genericTrieTraverse

  default trieShowsPrec ::
    ( Show a, GTrieKeyShow (Rep k) , TrieRep k ~ TrieRepDefault k) =>
    Int -> Trie k a -> ShowS
  trieShowsPrec = genericTrieShowsPrec

  default select ::
    ( GTrieKey (Rep k), Generic k , TrieRep k ~ TrieRepDefault k) =>
    k -> Trie k a -> Trie k a
  select = genericSelect

  default mapMaybe ::
    ( GTrieKey (Rep k) , TrieRep k ~ TrieRepDefault k) =>
    (a -> Maybe b) -> Trie k a -> Trie k b
  mapMaybe = genericMapMaybe

  default foldWithKey ::
    ( GTrieKey (Rep k) , TrieRep k ~ TrieRepDefault k, Generic k) =>
    (k -> a -> r -> r) -> r -> Trie k a -> r
  foldWithKey = genericFoldWithKey

  default traverseWithKey ::
    ( GTrieKey (Rep k) , TrieRep k ~ TrieRepDefault k, Generic k, Applicative f) =>
    (k -> a -> f b) -> Trie k a -> f (Trie k b)
  traverseWithKey = genericTraverseWithKey

-- | The default implementation of a 'TrieRep' is 'GTrie' wrapped in
-- a 'Maybe'. This wrapping is due to the 'GTrie' being a non-empty
-- trie allowing all the of the "emptiness" to be represented at the
-- top level for any given generically implemented key.
type TrieRepDefault k = Compose Maybe (GTrie (Rep k))

-- | Effectively an associated datatype of tries indexable by keys of type @k@.
-- By using a separate newtype wrapper around the associated type synonym we're
-- able to use the same 'MkTrie' constructor for all of the generic
-- implementations while still getting the injectivity of a new type.
newtype Trie k a = MkTrie (TrieRep k a)


------------------------------------------------------------------------------
-- Manually derived instances for base types
------------------------------------------------------------------------------

-- | 'Int' tries are implemented with 'IntMap'.
instance TrieKey Int where
  type TrieRep Int              = IntMap
  lookup k (MkTrie x)           = IntMap.lookup k x
  insert k v (MkTrie t)         = MkTrie (IntMap.insert k v t)
  delete k (MkTrie t)           = MkTrie (IntMap.delete k t)
  empty                         = MkTrie IntMap.empty
  singleton k v                 = MkTrie (IntMap.singleton k v)
  trieNull (MkTrie x)           = IntMap.null x
  trieMap f (MkTrie x)          = MkTrie (IntMap.map f x)
  trieFold f (MkTrie x) z       = IntMap.foldr f z x
  trieTraverse f (MkTrie x)     = fmap MkTrie (traverse f x)
  trieShowsPrec p (MkTrie x)    = showsPrec p x
  select k (MkTrie x)           = case IntMap.lookup k x of
                                    Nothing -> MkTrie IntMap.empty
                                    Just v  -> MkTrie (IntMap.singleton k v)
  mapMaybe f (MkTrie x)         = MkTrie (IntMap.mapMaybe f x)
  foldWithKey f z (MkTrie x)    = IntMap.foldWithKey f z x
  traverseWithKey f (MkTrie x)  = fmap MkTrie (IntMap.traverseWithKey f x)
  {-# INLINE empty #-}
  {-# INLINE insert #-}
  {-# INLINE lookup #-}
  {-# INLINE delete #-}
  {-# INLINE foldWithKey #-}
  {-# INLINE trieTraverse #-}
  {-# INLINE trieNull #-}
  {-# INLINE trieMap #-}
  {-# INLINE trieFold #-}

-- | 'Integer' tries are implemented with 'Map'.
instance TrieKey Integer where
  type TrieRep Integer          = Map Integer
  lookup k (MkTrie t)           = Map.lookup k t
  insert k v (MkTrie t)         = MkTrie (Map.insert k v t)
  delete k (MkTrie t)           = MkTrie (Map.delete k t)
  empty                         = MkTrie Map.empty
  singleton k v                 = MkTrie (Map.singleton k v)
  trieNull (MkTrie x)           = Map.null x
  trieMap f (MkTrie x)          = MkTrie (Map.map f x)
  trieFold f (MkTrie x) z       = Map.foldr f z x
  trieTraverse f (MkTrie x)     = fmap MkTrie (traverse f x)
  trieShowsPrec p (MkTrie x)    = showsPrec p x
  select k (MkTrie x)           = case Map.lookup k x of
                                    Nothing -> MkTrie Map.empty
                                    Just v  -> MkTrie (Map.singleton k v)
  mapMaybe f (MkTrie x)         = MkTrie (Map.mapMaybe f x)
  foldWithKey f z (MkTrie x)    = Map.foldrWithKey f z x
  traverseWithKey f (MkTrie x)  = fmap MkTrie (Map.traverseWithKey f x)
  {-# INLINE empty #-}
  {-# INLINE insert #-}
  {-# INLINE lookup #-}
  {-# INLINE delete #-}
  {-# INLINE trieNull #-}
  {-# INLINE trieMap #-}
  {-# INLINE trieFold #-}
  {-# INLINE foldWithKey #-}
  {-# INLINE trieTraverse #-}

-- | 'Char tries are implemented with 'IntMap'.
instance TrieKey Char where
  type TrieRep Char             = IntMap
  lookup k (MkTrie t)           = IntMap.lookup (ord k) t
  delete k (MkTrie t)           = MkTrie (IntMap.delete (ord k) t)
  insert k v (MkTrie t)         = MkTrie (IntMap.insert (ord k) v t)
  empty                         = MkTrie IntMap.empty
  singleton k v                 = MkTrie (IntMap.singleton (ord k) v)
  trieNull (MkTrie x)           = IntMap.null x
  trieMap f (MkTrie x)          = MkTrie (IntMap.map f x)
  trieFold f (MkTrie x) z       = IntMap.foldr f z x
  trieTraverse f (MkTrie x)     = fmap MkTrie (traverse f x)
  trieShowsPrec p (MkTrie x)    = showsPrec p x
  select k (MkTrie x)           = case IntMap.lookup (ord k) x of
                                    Nothing -> MkTrie IntMap.empty
                                    Just v  -> MkTrie (IntMap.singleton (ord k) v)
  mapMaybe f (MkTrie x)         = MkTrie (IntMap.mapMaybe f x)
  foldWithKey f z (MkTrie x)    = IntMap.foldrWithKey (f . chr) z x
  traverseWithKey f (MkTrie x)  = fmap MkTrie (IntMap.traverseWithKey (f . chr) x)
  {-# INLINE empty #-}
  {-# INLINE insert #-}
  {-# INLINE lookup #-}
  {-# INLINE delete #-}
  {-# INLINE trieNull #-}
  {-# INLINE trieTraverse #-}
  {-# INLINE trieMap #-}
  {-# INLINE foldWithKey #-}
  {-# INLINE trieFold #-}

newtype OrdKey k = OrdKey k
  deriving (Read, Show, Eq, Ord)

-- | 'OrdKey' tries are implemented with 'Map', this is
-- intended for cases where it is better for some reason
-- to force the use of a 'Map' than to use the generically
-- derived structure.
instance (Show k, Ord k) => TrieKey (OrdKey k) where
  type TrieRep (OrdKey k)               = Map k
  lookup (OrdKey k) (MkTrie x)          = Map.lookup k x
  insert (OrdKey k) v (MkTrie x)        = MkTrie (Map.insert k v x)
  delete (OrdKey k) (MkTrie x)          = MkTrie (Map.delete k x)
  empty                                 = MkTrie Map.empty
  singleton (OrdKey k) v                = MkTrie (Map.singleton k v)
  trieNull (MkTrie x)                   = Map.null x
  trieMap f (MkTrie x)                  = MkTrie (Map.map f x)
  trieFold f (MkTrie x) z               = Map.foldr f z x
  trieTraverse f (MkTrie x)             = fmap MkTrie (traverse f x)
  trieShowsPrec p (MkTrie x)            = showsPrec p x
  select (OrdKey k) (MkTrie x)          = case Map.lookup k x of
                                            Nothing -> MkTrie Map.empty
                                            Just v  -> MkTrie (Map.singleton k v)
  mapMaybe f (MkTrie x)                 = MkTrie (Map.mapMaybe f x)
  foldWithKey f z (MkTrie x)            = Map.foldrWithKey (f . OrdKey) z x
  traverseWithKey f (MkTrie x)          = fmap MkTrie (Map.traverseWithKey (f . OrdKey) x)
  {-# INLINE empty #-}
  {-# INLINE insert #-}
  {-# INLINE lookup #-}
  {-# INLINE delete #-}
  {-# INLINE foldWithKey #-}
  {-# INLINE trieNull #-}
  {-# INLINE trieMap #-}
  {-# INLINE trieFold #-}
  {-# INLINE trieTraverse #-}
  {-# INLINE trieShowsPrec #-}

------------------------------------------------------------------------------
-- Automatically derived instances for common types
------------------------------------------------------------------------------

instance                                      TrieKey ()
instance                                      TrieKey Bool
instance TrieKey k                         => TrieKey (Maybe k)
instance (TrieKey a, TrieKey b)            => TrieKey (Either a b)
instance (TrieKey a, TrieKey b)            => TrieKey (a,b)
instance (TrieKey a, TrieKey b, TrieKey c) => TrieKey (a,b,c)
instance TrieKey k                         => TrieKey [k]

------------------------------------------------------------------------------
-- Generic 'TrieKey' method implementations
------------------------------------------------------------------------------

-- | Generic implementation of 'lookup'. This is the default implementation.
genericLookup ::
    ( GTrieKey (Rep k), Generic k
    , TrieRep k ~ TrieRepDefault k
    ) =>
    k -> Trie k a -> Maybe a
genericLookup k (MkTrie (Compose t)) = gtrieLookup (from k) =<< t
{-# INLINABLE genericLookup #-}

-- | Generic implementation of 'trieNull'. This is the default implementation.
genericTrieNull ::
    ( TrieRep k ~ TrieRepDefault k
    ) =>
    Trie k a -> Bool
genericTrieNull (MkTrie (Compose mb)) = isNothing mb
{-# INLINABLE genericTrieNull #-}

-- | Generic implementation of 'singleton'. This is the default implementation.
genericSingleton ::
    ( GTrieKey (Rep k), Generic k
    , TrieRep k ~ TrieRepDefault k
    ) =>
    k -> a -> Trie k a
genericSingleton k v = MkTrie $ Compose $ Just $! gtrieSingleton (from k) v
{-# INLINABLE genericSingleton #-}

-- | Generic implementation of 'empty'. This is the default implementation.
genericEmpty ::
    ( TrieRep k ~ TrieRepDefault k
    ) =>
    Trie k a
genericEmpty = MkTrie (Compose Nothing)
{-# INLINABLE genericEmpty #-}

-- | Generic implementation of 'insert'. This is the default implementation.
genericInsert ::
    ( GTrieKey (Rep k), Generic k
    , TrieRep k ~ TrieRepDefault k
    ) =>
    k -> a -> Trie k a -> Trie k a
genericInsert k v (MkTrie (Compose m)) =
  case m of
    Nothing -> MkTrie (Compose (Just $! gtrieSingleton (from k) v))
    Just t  -> MkTrie (Compose (Just $! gtrieInsert (from k) v t))
{-# INLINABLE genericInsert #-}

-- | Generic implementation of 'delete'. This is the default implementation.
genericDelete ::
    ( GTrieKey (Rep k), Generic k
    , TrieRep k ~ TrieRepDefault k
    ) =>
    k -> Trie k a -> Trie k a
genericDelete k (MkTrie (Compose m)) = MkTrie (Compose (gtrieDelete (from k) =<< m))
{-# INLINABLE genericDelete #-}

-- | Generic implementation of 'trieMap'. This is the default implementation.
genericTrieMap ::
    ( GTrieKey (Rep k)
    , TrieRep k ~ TrieRepDefault k
    ) =>
    (a -> b) -> Trie k a -> Trie k b
genericTrieMap f (MkTrie (Compose x)) = MkTrie (Compose (fmap (gtrieMap f) $! x))
{-# INLINABLE genericTrieMap #-}

-- | Generic implementation of 'trieFold'. This is the default implementation.
genericTrieFold ::
    ( GTrieKey (Rep k)
    , TrieRep k ~ TrieRepDefault k
    ) =>
    (a -> b -> b) -> Trie k a -> b -> b
genericTrieFold f (MkTrie (Compose m)) z =
  case m of
    Just x  -> gtrieFold f x z
    Nothing -> z
{-# INLINABLE genericTrieFold #-}

-- | Generic implementation of 'trieTraverse'. This is the default implementation.
genericTrieTraverse ::
    ( GTrieKey (Rep k)
    , TrieRep k ~ TrieRepDefault k
    , Applicative f
    ) =>
    (a -> f b) -> Trie k a -> f (Trie k b)
genericTrieTraverse f (MkTrie (Compose x)) =
  fmap (MkTrie . Compose) (traverse (gtrieTraverse f) x)
{-# INLINABLE genericTrieTraverse #-}

-- | Generic implementation of 'trieShowsPrec'. This is the default implementation.
genericTrieShowsPrec ::
    ( Show a, GTrieKeyShow (Rep k)
    , TrieRep k ~ TrieRepDefault k
    ) =>
    Int -> Trie k a -> ShowS
genericTrieShowsPrec p (MkTrie (Compose m)) =
  case m of
    Just x  -> showsPrec p x
    Nothing -> showString "()"
{-# INLINABLE genericTrieShowsPrec #-}

-- | Generic implementation of 'select'. This is the default implementation.
genericSelect ::
    ( GTrieKey (Rep k), Generic k
    , TrieRep k ~ TrieRepDefault k
    ) =>
    k -> Trie k a -> Trie k a
genericSelect k (MkTrie (Compose x)) = MkTrie (Compose (gselect (from k) =<< x))
{-# INLINABLE genericSelect #-}

-- | Generic implementation of 'mapMaybe'. This is the default implementation.
genericMapMaybe ::
    ( GTrieKey (Rep k)
    , TrieRep k ~ TrieRepDefault k
    ) =>
    (a -> Maybe b) -> Trie k a -> Trie k b
genericMapMaybe f (MkTrie (Compose x)) = MkTrie (Compose (gmapMaybe f =<< x))
{-# INLINABLE genericMapMaybe #-}

-- | Generic implementation of 'foldWithKey'. This is the default implementation.
genericFoldWithKey ::
    ( GTrieKey (Rep k), Generic k
    , TrieRep k ~ TrieRepDefault k
    ) =>
    (k -> a -> r -> r) -> r -> Trie k a -> r
genericFoldWithKey f z (MkTrie (Compose m)) =
  case m of
    Nothing -> z
    Just x  -> gfoldWithKey (f . to) z x
{-# INLINABLE genericFoldWithKey #-}

-- | Generic implementation of 'traverseWithKey'. This is the default implementation.
genericTraverseWithKey ::
    ( GTrieKey (Rep k), Generic k
    , TrieRep k ~ TrieRepDefault k
    , Applicative f
    ) =>
    (k -> a -> f b) -> Trie k a -> f (Trie k b)
genericTraverseWithKey f (MkTrie (Compose m)) = fmap (MkTrie . Compose) (traverse (gtraverseWithKey (f . to)) m)
{-# INLINABLE genericTraverseWithKey #-}


------------------------------------------------------------------------------
-- Generic implementation class
------------------------------------------------------------------------------

-- | Mapping of generic representation of keys to trie structures.
data    family   GTrie (f :: * -> *) a
newtype instance GTrie (M1 i c f) a     = MTrie (GTrie f a)
data    instance GTrie (f :+: g)  a     = STrieL !(GTrie f a) | STrieR !(GTrie g a)
                                        | STrieB !(GTrie f a) !(GTrie g a)
newtype instance GTrie (f :*: g)  a     = PTrie (GTrie f (GTrie g a))
newtype instance GTrie (K1 i k)   a     = KTrie (Trie k a)
newtype instance GTrie U1         a     = UTrie a
data    instance GTrie V1         a

instance GTrieKey f => Functor (GTrie f) where
  fmap = gtrieMap

-- | TrieKey operations on Generic representations used to provide
-- the default implementations of tries.
class GTrieKey f where
  gtrieLookup    :: f p -> GTrie f a -> Maybe a
  gtrieInsert    :: f p -> a -> GTrie f a -> GTrie f a
  gtrieSingleton :: f p -> a -> GTrie f a
  gtrieDelete    :: f p -> GTrie f a -> Maybe (GTrie f a)
  gtrieMap       :: (a -> b) -> GTrie f a -> GTrie f b
  gtrieFold      :: (a -> b -> b) -> GTrie f a -> b -> b
  gtrieTraverse  :: Applicative m => (a -> m b) -> GTrie f a -> m (GTrie f b)
  gselect        :: f p -> GTrie f a -> Maybe (GTrie f a)
  gmapMaybe      :: (a -> Maybe b) -> GTrie f a -> Maybe (GTrie f b)
  gfoldWithKey   :: (f p -> a -> r -> r) -> r -> GTrie f a -> r
  gtraverseWithKey :: Applicative m => (f p -> a -> m b) -> GTrie f a -> m (GTrie f b)

-- | The 'GTrieKeyShow' class provides generic implementations
-- of 'showsPrec'. This class is separate due to its implementation
-- varying for diferent kinds of metadata.
class GTrieKeyShow f where
  gtrieShowsPrec :: Show a => Int -> GTrie f a -> ShowS

------------------------------------------------------------------------------
-- Generic implementation for metadata
------------------------------------------------------------------------------

-- | Generic metadata is skipped in trie representation and operations.
instance GTrieKey f => GTrieKey (M1 i c f) where
  gtrieLookup (M1 k) (MTrie x)  = gtrieLookup k x
  gtrieInsert (M1 k) v (MTrie t)= MTrie (gtrieInsert k v t)
  gtrieSingleton (M1 k) v       = MTrie (gtrieSingleton k v)
  gtrieDelete (M1 k) (MTrie x)  = fmap MTrie (gtrieDelete k x)
  gtrieMap f (MTrie x)          = MTrie (gtrieMap f x)
  gtrieFold f (MTrie x)         = gtrieFold f x
  gtrieTraverse f (MTrie x)     = fmap MTrie (gtrieTraverse f x)
  gselect (M1 k) (MTrie x)      = fmap MTrie (gselect k x)
  gmapMaybe f (MTrie x)         = fmap MTrie (gmapMaybe f x)
  gfoldWithKey f z (MTrie x)         = gfoldWithKey (f . M1) z x
  gtraverseWithKey f (MTrie x)  = fmap MTrie (gtraverseWithKey (f . M1) x)
  {-# INLINE gtrieLookup #-}
  {-# INLINE gtrieInsert #-}
  {-# INLINE gtrieSingleton #-}
  {-# INLINE gtrieDelete #-}
  {-# INLINE gtrieMap #-}
  {-# INLINE gtrieFold #-}
  {-# INLINE gtrieTraverse #-}
  {-# INLINE gfoldWithKey #-}
  {-# INLINE gtraverseWithKey #-}

data MProxy c (f :: * -> *) a = MProxy

instance GTrieKeyShow f => GTrieKeyShow (M1 D d f) where
  gtrieShowsPrec p (MTrie x)    = showsPrec p x
instance (Constructor c, GTrieKeyShow f) => GTrieKeyShow (M1 C c f) where
  gtrieShowsPrec p (MTrie x)    = showParen (p > 10)
                                $ showString "Con "
                                . shows (conName (MProxy :: MProxy c f ()))
                                . showString " "
                                . showsPrec 11 x
instance GTrieKeyShow f => GTrieKeyShow (M1 S s f) where
  gtrieShowsPrec p (MTrie x)    = showsPrec p x

------------------------------------------------------------------------------
-- Generic implementation for fields
------------------------------------------------------------------------------

checkNull :: TrieKey k => Trie k a -> Maybe (Trie k a)
checkNull x
  | trieNull x = Nothing
  | otherwise  = Just x

-- | Generic fields are represented by tries of the field type.
instance TrieKey k => GTrieKey (K1 i k) where
  gtrieLookup (K1 k) (KTrie x)          = lookup k x
  gtrieInsert (K1 k) v (KTrie t)        = KTrie (insert k v t)
  gtrieSingleton (K1 k) v               = KTrie (singleton k v)
  gtrieDelete (K1 k) (KTrie t)          = fmap KTrie (checkNull (delete k t))
  gtrieMap f (KTrie x)                  = KTrie (trieMap f x)
  gtrieFold f (KTrie x )                = trieFold f x
  gtrieTraverse f (KTrie x)             = fmap KTrie (traverse f x)
  gselect (K1 k) (KTrie x)              = fmap KTrie (checkNull (select k x))
  gmapMaybe f (KTrie x)                 = fmap KTrie (checkNull (mapMaybe f x))
  gfoldWithKey f z (KTrie x)            = foldWithKey (f . K1) z x
  gtraverseWithKey f (KTrie x)          = fmap KTrie (traverseWithKey (f . K1) x)
  {-# INLINE gtrieLookup #-}
  {-# INLINE gtrieInsert #-}
  {-# INLINE gtrieSingleton #-}
  {-# INLINE gtrieDelete #-}
  {-# INLINE gtrieMap #-}
  {-# INLINE gtrieFold #-}
  {-# INLINE gtrieTraverse #-}
  {-# INLINE gfoldWithKey #-}
  {-# INLINE gtraverseWithKey #-}

instance TrieKey k => GTrieKeyShow (K1 i k) where
  gtrieShowsPrec p (KTrie x)            = showsPrec p x

------------------------------------------------------------------------------
-- Generic implementation for products
------------------------------------------------------------------------------

-- | Generic products are represented by tries of tries.
instance (GTrieKey f, GTrieKey g) => GTrieKey (f :*: g) where

  gtrieLookup (i :*: j) (PTrie x)       = gtrieLookup j =<< gtrieLookup i x
  gtrieInsert (i :*: j) v (PTrie t)     = case gtrieLookup i t of
                                            Nothing -> PTrie (gtrieInsert i (gtrieSingleton j v) t)
                                            Just ti -> PTrie (gtrieInsert i (gtrieInsert j v ti) t)
  gtrieDelete (i :*: j) (PTrie t)       = case gtrieLookup i t of
                                            Nothing -> Just (PTrie t)
                                            Just ti -> case gtrieDelete j ti of
                                                         Nothing -> fmap PTrie $! gtrieDelete i t
                                                         Just tj -> Just (PTrie (gtrieInsert i tj t))
  gtrieSingleton (i :*: j) v            = PTrie (gtrieSingleton i (gtrieSingleton j v))
  gtrieMap f (PTrie x)                  = PTrie (gtrieMap (gtrieMap f) x)
  gtrieFold f (PTrie x)                 = gtrieFold (gtrieFold f) x
  gtrieTraverse f (PTrie x)             = fmap PTrie (gtrieTraverse (gtrieTraverse f) x)
  gselect (i :*: j) (PTrie x)           = fmap PTrie (gmapMaybe (gselect j) =<< gselect i x)
  gmapMaybe f (PTrie x)                 = fmap PTrie (gmapMaybe (gmapMaybe f) x)
  gfoldWithKey f z (PTrie x)            = gfoldWithKey (\i m r -> gfoldWithKey (\j -> f (i:*:j)) r m) z x
  gtraverseWithKey f (PTrie x)          = fmap PTrie (gtraverseWithKey (\i ->
                                                      gtraverseWithKey (\j -> f (i :*: j))) x)
  {-# INLINE gtrieLookup #-}
  {-# INLINE gtrieInsert #-}
  {-# INLINE gtrieDelete #-}
  {-# INLINE gtrieSingleton #-}
  {-# INLINE gtrieMap #-}
  {-# INLINE gtrieFold #-}
  {-# INLINE gtrieTraverse #-}
  {-# INLINE gfoldWithKey #-}
  {-# INLINE gtraverseWithKey #-}

instance (GTrieKeyShow f, GTrieKeyShow g) => GTrieKeyShow (f :*: g) where
  gtrieShowsPrec p (PTrie x)            = showsPrec p x


------------------------------------------------------------------------------
-- Generic implementation for sums
------------------------------------------------------------------------------

-- | Generic sums are represented by up to a pair of sub-tries.
instance (GTrieKey f, GTrieKey g) => GTrieKey (f :+: g) where

  gtrieLookup (L1 k) (STrieL x)         = gtrieLookup k x
  gtrieLookup (L1 k) (STrieB x _)       = gtrieLookup k x
  gtrieLookup (R1 k) (STrieR y)         = gtrieLookup k y
  gtrieLookup (R1 k) (STrieB _ y)       = gtrieLookup k y
  gtrieLookup _      _                  = Nothing

  gtrieInsert (L1 k) v (STrieL x)       = STrieL (gtrieInsert k v x)
  gtrieInsert (L1 k) v (STrieR y)       = STrieB (gtrieSingleton k v) y
  gtrieInsert (L1 k) v (STrieB x y)     = STrieB (gtrieInsert k v x) y
  gtrieInsert (R1 k) v (STrieL x)       = STrieB x (gtrieSingleton k v)
  gtrieInsert (R1 k) v (STrieR y)       = STrieR (gtrieInsert k v y)
  gtrieInsert (R1 k) v (STrieB x y)     = STrieB x (gtrieInsert k v y)

  gtrieSingleton (L1 k) v               = STrieL (gtrieSingleton k v)
  gtrieSingleton (R1 k) v               = STrieR (gtrieSingleton k v)

  gtrieDelete (L1 k) (STrieL x)         = fmap STrieL (gtrieDelete k x)
  gtrieDelete (L1 _) (STrieR y)         = Just (STrieR y)
  gtrieDelete (L1 k) (STrieB x y)       = case gtrieDelete k x of
                                            Nothing -> Just (STrieR y)
                                            Just x' -> Just (STrieB x' y)
  gtrieDelete (R1 _) (STrieL x)         = Just (STrieL x)
  gtrieDelete (R1 k) (STrieR y)         = fmap STrieR (gtrieDelete k y)
  gtrieDelete (R1 k) (STrieB x y)       = case gtrieDelete k y of
                                            Nothing -> Just (STrieL x)
                                            Just y' -> Just (STrieB x y')

  gtrieMap f (STrieB x y)               = STrieB (gtrieMap f x) (gtrieMap f y)
  gtrieMap f (STrieL x)                 = STrieL (gtrieMap f x)
  gtrieMap f (STrieR y)                 = STrieR (gtrieMap f y)

  gtrieFold f (STrieB x y)              = gtrieFold f x . gtrieFold f y
  gtrieFold f (STrieL x)                = gtrieFold f x
  gtrieFold f (STrieR y)                = gtrieFold f y

  gtrieTraverse f (STrieB x y)          = liftA2 STrieB (gtrieTraverse f x) (gtrieTraverse f y)
  gtrieTraverse f (STrieL x)            = fmap STrieL (gtrieTraverse f x)
  gtrieTraverse f (STrieR y)            = fmap STrieR (gtrieTraverse f y)

  gselect (L1 k) (STrieL x)             = fmap STrieL (gselect k x)
  gselect (L1 k) (STrieB x _)           = fmap STrieL (gselect k x)
  gselect (R1 k) (STrieR y)             = fmap STrieR (gselect k y)
  gselect (R1 k) (STrieB _ y)           = fmap STrieR (gselect k y)
  gselect _      _                      = Nothing

  gmapMaybe f (STrieL x)                = fmap STrieL (gmapMaybe f x)
  gmapMaybe f (STrieR y)                = fmap STrieR (gmapMaybe f y)
  gmapMaybe f (STrieB x y)              = case (gmapMaybe f x, gmapMaybe f y) of
                                            (Nothing, Nothing) -> Nothing
                                            (Just x', Nothing) -> Just (STrieL x')
                                            (Nothing, Just y') -> Just (STrieR y')
                                            (Just x', Just y') -> Just (STrieB x' y')
  gfoldWithKey f z (STrieL x)           = gfoldWithKey (f . L1) z x
  gfoldWithKey f z (STrieR y)           = gfoldWithKey (f . R1) z y
  gfoldWithKey f z (STrieB x y)         = gfoldWithKey (f . L1) (gfoldWithKey (f . R1) z y) x

  gtraverseWithKey f (STrieL x)         = fmap STrieL (gtraverseWithKey (f . L1) x)
  gtraverseWithKey f (STrieR y)         = fmap STrieR (gtraverseWithKey (f . R1) y)
  gtraverseWithKey f (STrieB x y)       = liftA2 STrieB (gtraverseWithKey (f . L1) x)
                                                        (gtraverseWithKey (f . R1) y)
  {-# INLINE gtrieLookup #-}
  {-# INLINE gtrieInsert #-}
  {-# INLINE gtrieDelete #-}
  {-# INLINE gtrieSingleton #-}
  {-# INLINE gtrieFold #-}
  {-# INLINE gtrieTraverse #-}
  {-# INLINE gtrieMap #-}
  {-# INLINE gfoldWithKey #-}
  {-# INLINE gtraverseWithKey #-}

instance (GTrieKeyShow f, GTrieKeyShow g) => GTrieKeyShow (f :+: g) where
  gtrieShowsPrec p (STrieB x y)         = showParen (p > 10)
                                        $ showString "STrieB "
                                        . showsPrec 11 x
                                        . showString " "
                                        . showsPrec 11 y
  gtrieShowsPrec p (STrieL x)           = showParen (p > 10)
                                        $ showString "STrieL "
                                        . showsPrec 11 x
  gtrieShowsPrec p (STrieR y)           = showParen (p > 10)
                                        $ showString "STrieR "
                                        . showsPrec 11 y

------------------------------------------------------------------------------
-- Generic implementation for units
------------------------------------------------------------------------------

-- | Tries of constructors without fields are represented by a single value.
instance GTrieKey U1 where
  gtrieLookup _ (UTrie x)       = Just x
  gtrieInsert _ v _             = UTrie v
  gtrieDelete _ _               = Nothing
  gtrieSingleton _              = UTrie
  gtrieMap f (UTrie x)          = UTrie (f x)
  gtrieFold f (UTrie x)         = f x
  gtrieTraverse f (UTrie x)     = fmap UTrie (f x)
  gselect _ x                   = Just x
  gmapMaybe f (UTrie x)         = fmap UTrie (f x)
  gfoldWithKey f z (UTrie x)    = f U1 x z
  gtraverseWithKey f (UTrie x)  = fmap UTrie (f U1 x)
  {-# INLINE gtrieLookup #-}
  {-# INLINE gtrieInsert #-}
  {-# INLINE gtrieDelete #-}
  {-# INLINE gtrieSingleton #-}
  {-# INLINE gtrieFold #-}
  {-# INLINE gtrieTraverse #-}
  {-# INLINE gtrieMap #-}
  {-# INLINE gfoldWithKey #-}
  {-# INLINE gtraverseWithKey #-}

instance GTrieKeyShow U1 where
  gtrieShowsPrec p (UTrie x)    = showsPrec p x

------------------------------------------------------------------------------
-- Generic implementation for empty types
------------------------------------------------------------------------------

-- | Tries of types without constructors are represented by a unit.
instance GTrieKey V1 where
  gtrieLookup k t               = k `seq` t `seq` error "GTrieKey.V1: gtrieLookup"
  gtrieInsert k _ t             = k `seq` t `seq` error "GTrieKey.V1: gtrieInsert"
  gtrieDelete k t               = k `seq` t `seq` error "GTrieKey.V1: gtrieDelete"
  gtrieSingleton k _            = k `seq` error "GTrieKey.V1: gtrieSingleton"
  gtrieMap _ t                  = t `seq` error "GTrieKey.V1: gtrieMap"
  gtrieFold _ _ t               = t `seq` error "GTrieKey.V1: gtrieFold"
  gtrieTraverse _ t             = t `seq` error "GTrieKey.V1: gtrieTraverse"
  gselect k t                   = k `seq` t `seq` error "GTrieKey.V1: gselect"
  gmapMaybe _ t                 = t `seq` error "GTrieKey.V1: gmapMaybe"
  gfoldWithKey _ _ t            = t `seq` error "GTrieKey.V1: gmapFoldWithKey"
  gtraverseWithKey _ t          = t `seq` error "GTrieKey.V1: gtraverseWithKey"
  {-# INLINE gtrieLookup #-}
  {-# INLINE gtrieInsert #-}
  {-# INLINE gtrieDelete #-}
  {-# INLINE gtrieSingleton #-}
  {-# INLINE gtrieFold #-}
  {-# INLINE gtrieMap #-}
  {-# INLINE gtrieTraverse #-}
  {-# INLINE gfoldWithKey #-}
  {-# INLINE gtraverseWithKey #-}

instance GTrieKeyShow V1 where
  gtrieShowsPrec _ _            = showString "()"

------------------------------------------------------------------------------
-- Various helpers
------------------------------------------------------------------------------

-- | Construct a trie from a list of key/value pairs
fromList :: TrieKey k => [(k,v)] -> Trie k v
fromList = foldl' (\acc (k,v) -> insert k v acc) empty

-- | Alter the values of a trie. The function will take the value stored
-- as the given key if one exists and should return a value to insert at
-- that location or Nothing to delete from that location.
alter :: TrieKey k => k -> (Maybe a -> Maybe a) -> Trie k a -> Trie k a
alter k f t =
  case f (lookup k t) of
    Just v' -> insert k v' t
    Nothing -> delete k t

-- | Returns 'True' when the 'Trie' has a value stored at the given key.
member :: TrieKey k => k -> Trie k a -> Bool
member k t = isJust (lookup k t)

-- | Returns 'False' when the 'Trie' has a value stored at the given key.
notMember :: TrieKey k => k -> Trie k a -> Bool
notMember k t = isNothing (lookup k t)

-- | Transform 'Trie' to an association list.
toList :: TrieKey k => Trie k a -> [(k,a)]
toList = foldWithKey (\k v xs -> (k,v) : xs) []

------------------------------------------------------------------------------
-- Various instances for Trie
------------------------------------------------------------------------------

instance (Show a, TrieKey  k) => Show (Trie  k a) where
  showsPrec = trieShowsPrec

instance (Show a, GTrieKeyShow f) => Show (GTrie f a) where
  showsPrec = gtrieShowsPrec

instance TrieKey k => Functor (Trie k) where
  fmap = trieMap

instance TrieKey k => Foldable (Trie k) where
  foldr f z t = trieFold f t z

instance TrieKey k => Traversable (Trie k) where
  traverse = trieTraverse
