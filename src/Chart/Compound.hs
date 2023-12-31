{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}

module Chart.Compound
  ( runHudCompoundWith,
    compoundMerge,
    writeChartOptionsCompound,
  )
where

import Prelude
import Chart
import Data.ByteString.Char8 qualified as C
import Data.List qualified as List
import Optics.Core
import Control.Monad.Trans.State.Lazy
import MarkupParse

-- * compounding
writeChartOptionsCompound :: FilePath -> [ChartOptions] -> IO ()
writeChartOptionsCompound fp cs = C.writeFile fp (encodeChartOptionsCompound cs)

encodeChartOptionsCompound :: [ChartOptions] -> C.ByteString
encodeChartOptionsCompound [] = mempty
encodeChartOptionsCompound cs@(c0:_) =
  markdown_ (view (#markupOptions % #renderStyle) c0) Xml  (markupChartOptionsCompound cs)

markupChartOptionsCompound :: [ChartOptions] -> Markup
markupChartOptionsCompound [] = mempty
markupChartOptionsCompound cs@(co0 : _) =
    header
      (view (#markupOptions % #markupHeight) co0)
      viewbox
      ( markupCssOptions (view (#markupOptions % #cssOptions) co0)
          <> (markupChartTree csAndHuds)
      )
  where
    viewbox = singletonGuard (view styleBox' csAndHuds)
    csAndHuds = addHudCompound (zip (view #hudOptions <$> cs) (view #charts <$> cs))

-- | Merge a list of ChartOptions, treating each element as charts to be merged. Note that this routine empties the hud options and converts them to charts.
compoundMerge :: [ChartOptions] -> ChartOptions
compoundMerge [] = mempty
compoundMerge cs@(c0 : _) =
  ChartOptions
    (view #markupOptions c0)
    (mempty & set #chartAspect (view (#hudOptions % #chartAspect) c0))
    (addHudCompound (zip (view #hudOptions <$> cs) (view #charts <$> cs)))

-- | Decorate a ChartTree with HudOptions, merging the individual hud options.
addHudCompound :: [(HudOptions, ChartTree)] -> ChartTree
addHudCompound [] = mempty
addHudCompound ts@((ho0, cs0) : _) =
  runHudCompoundWith
    (initialCanvas (view #chartAspect ho0) cs0)
    (zip3 dbs hss css)
  where
    hss = zipWith (\i hs -> fmap (over #priority (+(Priority (i*0.1)))) hs) [0..] (fst <$> huds)
    dbs = snd <$> huds
    css = (snd <$> ts) -- <> (blank <$> dbs)
    huds = (\(ho, cs) -> toHuds ho (singletonGuard $ view box' cs)) <$> ts

-- | Combine a collection of chart trees that share a canvas box.
runHudCompoundWith ::
  -- | initial canvas
  CanvasBox ->
  -- | databox-huds-chart tuples representing independent chart trees occupying the same canvas space
  [(DataBox, [Hud], ChartTree)] ->
  -- | integrated chart tree
  ChartTree
runHudCompoundWith cb ts = hss
  where
    hss =
      ts &
      fmap (\(db,hs,_) -> fmap (over #hud (withStateT (#dataBox .~ db))) hs) &
      mconcat &
      prioritizeHuds &
      mapM_ (closes . fmap (view #hud)) &
      flip execState (HudChart css mempty undefined) &
      (\x -> group (Just "chart") [view #chart x] <> group (Just "hud") [view #hud x])

    css =
      ts &
      fmap (\(db,_,ct) -> over chart' (projectWith cb db) ct) &
      mconcat

prioritizeHuds :: [Hud] -> [[Hud]]
prioritizeHuds hss =
      hss
        & List.sortOn (view #priority)
        & List.groupBy (\a b -> view #priority a == view #priority b)

