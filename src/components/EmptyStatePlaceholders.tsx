import React from "react";
import { motion } from "framer-motion";
import Masonry from 'react-masonry-css';

interface EmptyStatePlaceholdersProps {
  breakpointColumnsObj: Record<string | number, number>;
  isDragging: boolean;
  placeholderHeights: number[];
}

const EmptyStatePlaceholders: React.FC<EmptyStatePlaceholdersProps> = ({ breakpointColumnsObj, isDragging, placeholderHeights }) => {
  return (
    <Masonry
      breakpointCols={breakpointColumnsObj}
      className={`my-masonry-grid ${isDragging ? 'opacity-30 blur-[1px]' : 'opacity-50'} transition-all duration-300`}
      columnClassName="my-masonry-grid_column"
    >
      {placeholderHeights.map((height, index) => (
        <div key={index} className="masonry-item">
          <motion.div
            className="rounded-lg overflow-hidden bg-gray-300 dark:bg-zinc-800 w-full transition-all duration-300"
            style={{ height: `${height}px` }}
            initial={{ opacity: 0 }}
            animate={{ opacity: isDragging ? 0.2 : 0.5 }}
            transition={{
              opacity: { duration: 0.5, delay: index * 0.05 }
            }}
          />
        </div>
      ))}
    </Masonry>
  );
};

export default EmptyStatePlaceholders;
