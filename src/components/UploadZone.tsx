
import React, { useCallback, useState, useEffect } from "react";
import { useToast } from "@/components/ui/use-toast";
import { validateImageFile } from "@/lib/imageUtils";
import { ImagePlus, Link } from "lucide-react";
import { Dialog, DialogContent, DialogTitle, DialogDescription, DialogFooter, DialogHeader } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

interface UploadZoneProps {
  onImageUpload: (file: File) => void;
  onUrlAdd: (url: string) => void;
  isUploading: boolean;
  children: React.ReactNode;
}

const UploadZone: React.FC<UploadZoneProps> = ({
  onImageUpload,
  onUrlAdd,
  isUploading,
  children,
}) => {
  const { toast } = useToast();
  const [isDragging, setIsDragging] = useState(false);
  const [urlModalOpen, setUrlModalOpen] = useState(false);
  const [inputUrl, setInputUrl] = useState("");

  const handleDragOver = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);
  }, []);

  const handleDrop = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);

    if (isUploading) return;

    const files = Array.from(e.dataTransfer.files);
    
    // Process the dropped files
    files.forEach((file) => {
      if (validateImageFile(file)) {
        onImageUpload(file);
      } else {
        toast({
          title: "Invalid file",
          description: "Please upload images less than 10MB in size.",
          variant: "destructive",
        });
      }
    });
  }, [isUploading, onImageUpload, toast]);

  const handleChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    if (!e.target.files || isUploading) return;
    
    const files = Array.from(e.target.files);
    
    files.forEach((file) => {
      if (validateImageFile(file)) {
        onImageUpload(file);
      } else {
        toast({
          title: "Invalid file",
          description: "Please upload images less than 10MB in size.",
          variant: "destructive",
        });
      }
    });
    
    // Reset the input
    e.target.value = "";
  }, [isUploading, onImageUpload, toast]);

  const handleUrlSubmit = useCallback((e: React.FormEvent) => {
    e.preventDefault();
    
    if (!inputUrl.trim()) {
      toast({
        title: "Invalid URL",
        description: "Please enter a valid URL.",
        variant: "destructive",
      });
      return;
    }
    
    // Simple URL validation
    try {
      const url = new URL(inputUrl);
      if (url.protocol !== 'http:' && url.protocol !== 'https:') {
        throw new Error("Invalid protocol");
      }
      
      onUrlAdd(inputUrl);
      setUrlModalOpen(false);
      setInputUrl("");
      
      toast({
        title: "URL added",
        description: "The URL card has been added to your collection.",
      });
    } catch (error) {
      toast({
        title: "Invalid URL",
        description: "Please enter a valid URL including http:// or https://.",
        variant: "destructive",
      });
    }
  }, [inputUrl, onUrlAdd, toast]);

  // Add paste event listener to capture pasted URLs
  useEffect(() => {
    const handlePaste = (e: ClipboardEvent) => {
      const pastedText = e.clipboardData?.getData('text');
      if (pastedText) {
        try {
          const url = new URL(pastedText);
          if (url.protocol === 'http:' || url.protocol === 'https:') {
            e.preventDefault();
            onUrlAdd(pastedText);
            toast({
              title: "URL added",
              description: "The URL card has been added to your collection.",
            });
          }
        } catch (error) {
          // Not a valid URL, ignore
        }
      }
    };

    document.addEventListener('paste', handlePaste);
    return () => {
      document.removeEventListener('paste', handlePaste);
    };
  }, [onUrlAdd, toast]);

  return (
    <>
      <div
        className={`min-h-screen w-full transition-all duration-300 ${
          isDragging ? "drag-active" : ""
        }`}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
      >
        {children}
        
        {isDragging && (
          <div className="fixed inset-0 bg-background/80 backdrop-blur-sm flex items-center justify-center z-50 pointer-events-none">
            <div className="bg-card p-8 rounded-lg shadow-lg flex flex-col items-center animate-float">
              <ImagePlus className="w-12 h-12 text-primary mb-4" />
              <p className="text-xl font-medium">Drop images to add</p>
            </div>
          </div>
        )}
        
        {isUploading && (
          <div className="fixed bottom-6 right-6 bg-card p-4 rounded-lg shadow-lg z-40 animate-slide-up">
            <p className="text-sm font-medium flex items-center">
              <span className="inline-block w-4 h-4 border-2 border-primary border-t-transparent rounded-full animate-spin mr-2"></span>
              Adding to collection...
            </p>
          </div>
        )}
        
        <input
          type="file"
          id="file-upload"
          className="hidden"
          accept="image/*"
          multiple
          onChange={handleChange}
        />
      </div>

      <Dialog open={urlModalOpen} onOpenChange={setUrlModalOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Add URL Card</DialogTitle>
            <DialogDescription>
              Enter a URL to add a website card to your collection.
            </DialogDescription>
          </DialogHeader>
          
          <form onSubmit={handleUrlSubmit}>
            <div className="py-4">
              <Input
                placeholder="https://example.com"
                value={inputUrl}
                onChange={(e) => setInputUrl(e.target.value)}
                className="w-full"
              />
            </div>
            
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setUrlModalOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={isUploading}>
                Add URL
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
};

export default UploadZone;
