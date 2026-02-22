import { useState, useCallback, useEffect, useRef } from "react";
import { toast } from "sonner";
import { ImageItem } from "./useImageStore";

export interface UseImageCollectionReturn {
  images: ImageItem[];
  trashItems: ImageItem[];
  isLoading: boolean;
  setImages: React.Dispatch<React.SetStateAction<ImageItem[]>>;
  setTrashItems: React.Dispatch<React.SetStateAction<ImageItem[]>>;
  deletedItemsHistory: ImageItem[][];
  setDeletedItemsHistory: React.Dispatch<React.SetStateAction<ImageItem[][]>>;
  removeImage: (id: string) => Promise<void>;
  removeImages: (ids: string[]) => Promise<void>;
  undoDelete: () => Promise<void>;
  emptyTrash: () => Promise<void>;
  shuffleImages: () => void;
  canUndo: boolean;
}

export function useImageCollection(): UseImageCollectionReturn {
  const [images, setImages] = useState<ImageItem[]>([]);
  const [trashItems, setTrashItems] = useState<ImageItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [deletedItemsHistory, setDeletedItemsHistory] = useState<ImageItem[][]>([]);

  // Ref to avoid stale closures in callbacks that need current images
  const imagesRef = useRef(images);
  imagesRef.current = images;

  // Load images on mount
  useEffect(() => {
    const loadImages = async () => {
      try {
        const [loadedImages, loadedTrashItems] = await Promise.all([
          window.electron.loadImages(),
          window.electron.listTrash()
        ]);
        
        // Sort by createdAt with newest first
        const sortedImages = [...(loadedImages || [])].sort((a, b) =>
          new Date(b.createdAt || 0).getTime() - new Date(a.createdAt || 0).getTime()
        );
        
        setImages(sortedImages);
        setTrashItems(loadedTrashItems || []);
      } catch (error) {
        console.error("Error loading images:", error);
        toast.error("Failed to load images");
      }
      setIsLoading(false);
    };

    loadImages();
  }, []);

  const removeImage = useCallback(async (id: string) => {
    try {
      const itemToDelete = imagesRef.current.find(img => img.id === id);
      if (!itemToDelete) return;

      await window.electron.deleteImage(id);

      // Update trash items list
      const updatedTrashItems = await window.electron.listTrash();
      setTrashItems(updatedTrashItems);
      setImages(prevImages => prevImages.filter(img => img.id !== id));

      // Add to history as a batch of one
      setDeletedItemsHistory(prev => [...prev, [itemToDelete]]);
    } catch (error) {
      console.error("Failed to delete image:", error);
      toast.error("Failed to delete image");
    }
  }, []);

  const removeImages = useCallback(async (ids: string[]) => {
    try {
      const idsSet = new Set(ids);
      const itemsToDelete = imagesRef.current.filter(img => idsSet.has(img.id));
      if (itemsToDelete.length === 0) return;

      await Promise.all(ids.map(id => window.electron.deleteImage(id)));

      const updatedTrashItems = await window.electron.listTrash();
      setTrashItems(updatedTrashItems);
      setImages(prevImages => prevImages.filter(img => !idsSet.has(img.id)));

      // Add entire batch as one undo entry
      setDeletedItemsHistory(prev => [...prev, itemsToDelete]);
    } catch (error) {
      console.error("Failed to delete images:", error);
      toast.error("Failed to delete images");
    }
  }, []);

  const undoDelete = useCallback(async () => {
    if (deletedItemsHistory.length === 0) return;

    try {
      // Get the last batch of deleted items
      const lastBatch = deletedItemsHistory[deletedItemsHistory.length - 1];

      // Restore all items in the batch
      await Promise.all(lastBatch.map(item => window.electron.restoreFromTrash(item.id)));

      const loadedImages = await window.electron.loadImages();

      // Insert all restored images back into their correct positions
      setImages(prevImages => {
        const newImages = [...prevImages];
        for (const item of lastBatch) {
          const restoredImage = loadedImages.find(img => img.id === item.id);
          if (restoredImage) {
            const insertIndex = newImages.findIndex(img =>
              new Date(img.createdAt).getTime() < new Date(restoredImage.createdAt).getTime()
            );
            const position = insertIndex === -1 ? newImages.length : insertIndex;
            newImages.splice(position, 0, restoredImage);
          }
        }
        return newImages;
      });

      // Remove the last batch from history
      setDeletedItemsHistory(prev => prev.slice(0, -1));
    } catch (error) {
      console.error("Failed to restore image:", error);
      toast.error("Failed to restore image");
    }
  }, [deletedItemsHistory]);

  const shuffleImages = useCallback(() => {
    setImages(prev => {
      const shuffled = [...prev];
      for (let i = shuffled.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
      }
      return shuffled;
    });
  }, []);

  const emptyTrash = useCallback(async () => {
    try {
      await window.electron.emptyTrash();
      setTrashItems([]);
      // Clear the history when emptying trash
      setDeletedItemsHistory([]);
    } catch (error) {
      console.error("Failed to empty trash:", error);
      toast.error("Failed to empty trash");
    }
  }, []);

  return {
    images,
    trashItems,
    isLoading,
    setImages,
    setTrashItems,
    deletedItemsHistory,
    setDeletedItemsHistory,
    removeImage,
    removeImages,
    undoDelete,
    emptyTrash,
    shuffleImages,
    canUndo: deletedItemsHistory.length > 0,
  };
}