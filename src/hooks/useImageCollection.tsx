import { useState, useCallback, useEffect } from "react";
import { toast } from "sonner";
import { ImageItem } from "./useImageStore";

export interface UseImageCollectionReturn {
  images: ImageItem[];
  trashItems: ImageItem[];
  isLoading: boolean;
  setImages: React.Dispatch<React.SetStateAction<ImageItem[]>>;
  setTrashItems: React.Dispatch<React.SetStateAction<ImageItem[]>>;
  deletedItemsHistory: ImageItem[];
  setDeletedItemsHistory: React.Dispatch<React.SetStateAction<ImageItem[]>>;
  removeImage: (id: string) => Promise<void>;
  undoDelete: () => Promise<void>;
  emptyTrash: () => Promise<void>;
  canUndo: boolean;
}

export function useImageCollection(): UseImageCollectionReturn {
  const [images, setImages] = useState<ImageItem[]>([]);
  const [trashItems, setTrashItems] = useState<ImageItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [deletedItemsHistory, setDeletedItemsHistory] = useState<ImageItem[]>([]);

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
      const itemToDelete = images.find(img => img.id === id);
      if (!itemToDelete) return;

      await window.electron.deleteImage(id);
      
      // Update trash items list
      const updatedTrashItems = await window.electron.listTrash();
      setTrashItems(updatedTrashItems);
      setImages(prevImages => prevImages.filter(img => img.id !== id));
      
      // Add to history
      setDeletedItemsHistory(prev => [...prev, itemToDelete]);
    } catch (error) {
      console.error("Failed to delete image:", error);
      toast.error("Failed to delete image");
    }
  }, [images]);

  const undoDelete = useCallback(async () => {
    if (deletedItemsHistory.length === 0) return;

    try {
      // Get the last deleted item
      const lastDeletedItem = deletedItemsHistory[deletedItemsHistory.length - 1];
      await window.electron.restoreFromTrash(lastDeletedItem.id);
      
      // Get the restored image
      const [loadedImages] = await Promise.all([
        window.electron.loadImages()
      ]);
      
      // Find the restored image in the loaded images
      const restoredImage = loadedImages.find(img => img.id === lastDeletedItem.id);
      if (!restoredImage) {
        throw new Error('Failed to find restored image');
      }

      // Insert the restored image back into its original position
      setImages(prevImages => {
        const newImages = [...prevImages];
        // Find the position where this image should be inserted
        const insertIndex = prevImages.findIndex(img => 
          new Date(img.createdAt).getTime() < new Date(restoredImage.createdAt).getTime()
        );
        // If no position found (should be at end), use length
        const position = insertIndex === -1 ? prevImages.length : insertIndex;
        newImages.splice(position, 0, restoredImage);
        return newImages;
      });

      // Remove the last item from history
      setDeletedItemsHistory(prev => prev.slice(0, -1));
    } catch (error) {
      console.error("Failed to restore image:", error);
      toast.error("Failed to restore image");
    }
  }, [deletedItemsHistory]);

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
    undoDelete,
    emptyTrash,
    canUndo: deletedItemsHistory.length > 0,
  };
}