MongoPercolator
================

Experiments inspired by Google Percolator built on MongoDB and using MongoMapper. We use this in production at [WordSwing](https://wordswing.com/about).

## Overview

MongoPercolator is a tool for keeping database documents up to date based as documents they depend on are updated. This leverages the natural dependency structure among documents, allows of parallelization, and reduces the need to perform batch computations.

The crux of MongoPercolator is mixin, `MongoPercolator::Node` which can be mixed in to any `MongoMapper::Document` class. In addition to the usual keys and associations of MongoMapper document models, Nodes also gain the ability to express operations that handle automatically recomputing the document's data if upstream data changes.

An `operation` involves a class that descends from `MongoPercolator::Operation`,
which encapsulates the computation for updating the node. A node may have one
or more operation, an operation may depend on one or more parent documents, and
an operation may be responsible for updating one or more properties of the
node.

Here's a basic node with one operation:

    class AlignedAudio
        include MongoPercolator::Node

        key :alignment, String

        class Realign < MongoPercolator::Operation

            # Declaring the parent documents creates associations that the
            # percolator can track to know when updates are necessary.
            declare_parent :sentence, :class => ChineseSentence
            declare_parent :audio, :class => Audio

            # Explicitly declaring what properties of the parents this operation requires
            # means that we only need to perform the operation when those properties change
            # not the any time the document is saved. This greatly limits unnessary updates.
            depends_on 'sentence.segmentation'
            depends_on 'audio.s3_path'

            # This block is executed in the context of the Audio node, so it has access to
            # the audio document's property s3_path as well as the instance method, 
            # forced_alignment. It uses the input helpers to retrieve the data it needs
            # from the parents. Only properties declared as dependencies can be accessed.
            emit do
                self.alignment = forced_alignment input('sentence.segmentation'), input('audio.s3_path')
            end
        end

        operation :realign

        def forced_alignment(seg, path)
            # perform forced alignment to align the audio file to the segmented text.
        end
    end

The above AlignedAudio document model stores timing data that matches up an
audio file with the segmented text of a Chinese sentence. This allows
WordSwing to play an audio recording of a Chinese sentence and highlight the
text as it plays, much like karaoke. Since we need to update the alignment when
either the audio file changes or when the text transcription of that audio file
changes, we make the operation depend on two parent documents, Audio and ChineseSentence.

    class Audio
        # Parents also need to be nodes.
        include MongoPercolator::Node

        key :s3_path, String
    end

    class ChineseSentence 
        include MongoPercolator::Node
        key :segmentation, String
    end

Notice that when we create an AlignedAudio model instance, the Audio and
ChineseSentence instances are properties on the Operation, not the Node itself:

    op = AlignedSentence::Realign.new(audio: a, sentence: s)
    aligned_audio = AlignedAudio.new(realign: op)
    aligned_audio.save

Whenever a node is saved, `MongoPercolator#propagate` is called, which searches
for any operations that depend on this document. Each identified operation is
marked as expired if it depends on properties of this node that have changed.

The process(es) doing percolation then simply need to identify expired
operations, and perform them as necessary, keeping the whole data graph up to
date.

### Operations

### Percolation

### Diffs

### Exports

## Installation

Add this line to your application's Gemfile:

    gem 'mongo_percolator'

And then execute:

    bundle

Or install it yourself as:

    gem install mongo_percolator

## Tests

I use `rspec` for unit tests. These can be run in the usual way:

    rspec spec

## Copyright

See LICENSE for details.
