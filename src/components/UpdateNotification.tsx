import React, { useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { X, RefreshCw } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useUpdateChecker } from '@/services/updateService';
import { useToast } from '@/components/ui/use-toast';

const UpdateNotification: React.FC = () => {
  const { updateState, installUpdate, notAvailableCount } = useUpdateChecker();
  const [dismissed, setDismissed] = React.useState(false);
  const { toast } = useToast();

  // Show "up to date" toast each time the "not available" event fires.
  // notAvailableCount starts at 0 and increments on each event, so
  // skipping count 0 avoids a false toast on mount.
  useEffect(() => {
    if (notAvailableCount > 0) {
      toast({
        title: 'No Updates Available',
        description: "You're running the latest version of SnapGrid.",
        duration: 3000,
      });
    }
  }, [notAvailableCount, toast]);

  // Reset dismissed when a new update download starts or finishes
  useEffect(() => {
    if (updateState.status === 'ready' || updateState.status === 'downloading') {
      setDismissed(false);
    }
  }, [updateState.status]);

  if (dismissed) return null;

  const visible =
    updateState.status === 'downloading' ||
    updateState.status === 'ready' ||
    updateState.status === 'error';

  if (!visible) return null;

  return (
    <AnimatePresence>
      <motion.div
        initial={{ opacity: 0, y: 50 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: 50 }}
        className="fixed bottom-4 right-4 z-50 max-w-sm bg-white dark:bg-zinc-800 rounded-lg shadow-lg border border-gray-200 dark:border-zinc-700 overflow-hidden"
      >
        <div className="p-4">
          {updateState.status === 'downloading' && (
            <>
              <h3 className="text-base font-semibold text-gray-900 dark:text-gray-100">
                Downloading Update
              </h3>
              <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
                {Math.round(updateState.progress.percent)}% complete
              </p>
              <div className="mt-2 w-full bg-gray-200 dark:bg-zinc-700 rounded-full h-1.5">
                <div
                  className="bg-blue-600 h-1.5 rounded-full transition-all"
                  style={{ width: `${updateState.progress.percent}%` }}
                />
              </div>
            </>
          )}

          {updateState.status === 'ready' && (
            <>
              <div className="flex justify-between items-start">
                <h3 className="text-base font-semibold text-gray-900 dark:text-gray-100">
                  Update Ready
                </h3>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-6 w-6 rounded-full -mt-1 -mr-1"
                  onClick={() => setDismissed(true)}
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>
              <p className="mt-1 text-sm text-gray-600 dark:text-gray-400">
                Version {updateState.info.version} is ready. Restart to apply.
              </p>
              <div className="mt-3">
                <Button
                  variant="default"
                  size="sm"
                  className="flex items-center gap-1.5"
                  onClick={installUpdate}
                >
                  <RefreshCw className="h-4 w-4" />
                  Restart to Update
                </Button>
              </div>
            </>
          )}

          {updateState.status === 'error' && (
            <>
              <div className="flex justify-between items-start">
                <h3 className="text-base font-semibold text-gray-900 dark:text-gray-100">
                  Update Error
                </h3>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-6 w-6 rounded-full -mt-1 -mr-1"
                  onClick={() => setDismissed(true)}
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>
              <p className="mt-1 text-sm text-gray-500 dark:text-gray-400 line-clamp-2">
                {updateState.message}
              </p>
            </>
          )}
        </div>
      </motion.div>
    </AnimatePresence>
  );
};

export default UpdateNotification;
